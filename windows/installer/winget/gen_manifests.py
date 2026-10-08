#!/usr/bin/env python3
"""Generate and validate the winget manifests for one VietTelex for Windows release.

    python3 windows/installer/winget/gen_manifests.py [--version X.Y.Z] [--out DIR]

* Version and installer URLs come from docs/stable.json ("windows" entry). For another
  version, URLs follow the published GitHub release layout:
      https://github.com/ptrinh/viettelex/releases/download/windows-v<V>/VietTelex-<V>-<arch>.msi
* Both MSIs are downloaded to a temp dir and hashed (SHA256). The GitHub release's own
  asset digest is cross-checked when the API reports one.
* ProductCode/UpgradeCode are read from each MSI with `msiinfo` (msitools) when it is
  installed; otherwise they are left out (winget then matches by ARP DisplayName/version).
* Output: <out>/manifests/p/ptrinh/VietTelex/<V>/ (version, installer, defaultLocale en-US,
  locale vi-VN), schema 1.12.0.
* Validation: every manifest is validated against the official winget JSON schema
  (fetched from github.com/microsoft/winget-cli). `jsonschema` is used if importable;
  otherwise a built-in validator covering every keyword those schemas use. Unknown keys
  are rejected (winget does the same). The emitted YAML is re-parsed (ruby's stdlib YAML,
  when present) and compared with the data to catch quoting mistakes.

Nothing is uploaded or submitted. See submit.sh for the PR commands.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
STABLE = os.path.join(ROOT, "docs", "stable.json")

PKG_ID = "ptrinh.VietTelex"
PKG_PATH = ("manifests", "p", "ptrinh", "VietTelex")
SCHEMA_VER = "1.12.0"
SCHEMA_URL = ("https://raw.githubusercontent.com/microsoft/winget-cli/master/schemas/JSON/"
              "manifests/v{v}/manifest.{t}.{v}.json")
REPO = "https://github.com/ptrinh/viettelex"
GH_ASSET = REPO + "/releases/download/windows-v{v}/VietTelex-{v}-{a}.msi"
GH_TAG = REPO + "/releases/tag/windows-v{v}"
ARCHES = ("x64", "arm64")

TAGS = ["vietnamese", "telex", "vni", "ime", "keyboard", "input-method", "tieng-viet", "bo-go"]

EN = {
    "ShortDescription": "Fast, private Vietnamese keyboard (Telex/VNI) for Windows: no underline, no data collection.",
    "Description": (
        "VietTelex is a Vietnamese input method for Windows 10 and 11, built on the Text Services "
        "Framework (TSF) - the system keyboard API. It needs no global keyboard hook, so it also "
        "works in Chrome, Edge, Excel and Word, and in apps running as administrator.\n"
        "\n"
        "- Telex or VNI, old or new tone placement, fix tones anywhere in the word.\n"
        "- No underline while typing; Command Prompt, PowerShell and Windows Terminal included.\n"
        "- Restores English words automatically and checks Vietnamese spelling.\n"
        "- Custom shortcuts; remembers Vietnamese/English per app; Ctrl+Shift, Alt+Z or Win+Space to switch.\n"
        "- Leaves password fields alone; turns itself off in Remote Desktop and virtual machines.\n"
        "- Native x64 and ARM64 builds.\n"
        "\n"
        "No telemetry: VietTelex collects no data and only goes online when you press Check for "
        "updates. Free and open source (MIT)."
    ),
}
VI = {
    "ShortDescription": "Bộ gõ tiếng Việt Telex/VNI nhanh, riêng tư cho Windows: không gạch chân, không thu thập dữ liệu.",
    "Description": (
        "VietTelex là bộ gõ tiếng Việt cho Windows 10 và 11, chạy trên Text Services Framework "
        "(TSF) - API bàn phím chính thức của Windows. Không cần hook bàn phím toàn cục, nên gõ được "
        "cả trong Chrome, Edge, Excel, Word và ứng dụng chạy quyền quản trị (Run as administrator).\n"
        "\n"
        "- Gõ Telex hoặc VNI, bỏ dấu kiểu mới hoặc cũ, sửa dấu ở bất kỳ vị trí nào trong từ.\n"
        "- Không gạch chân khi gõ, kể cả Command Prompt, PowerShell và Windows Terminal.\n"
        "- Tự khôi phục từ tiếng Anh, kiểm tra chính tả tiếng Việt.\n"
        "- Gõ tắt theo ý bạn; nhớ Việt/Anh theo từng ứng dụng; chuyển bằng Ctrl+Shift, Alt+Z hoặc Win+Space.\n"
        "- Không đụng vào ô mật khẩu; tự tắt trong Remote Desktop và máy ảo.\n"
        "- Bản x64 và ARM64 gốc.\n"
        "\n"
        "Không telemetry: VietTelex không thu thập dữ liệu, chỉ kết nối mạng khi bạn bấm Kiểm tra "
        "cập nhật. Miễn phí, mã nguồn mở (MIT)."
    ),
}


# ----------------------------------------------------------------------------- helpers
def fetch(url, dest=None, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": "viettelex-winget-gen"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    if dest:
        with open(dest, "wb") as f:
            f.write(data)
    return data


def msi_props(path):
    """ProductCode/UpgradeCode/ProductVersion from the MSI Property table, or {}."""
    if not shutil.which("msiinfo"):
        return {}
    try:
        out = subprocess.run(["msiinfo", "export", path, "Property"], capture_output=True,
                             text=True, check=True).stdout
    except (subprocess.CalledProcessError, OSError):
        return {}
    props = {}
    for line in out.replace("\r", "").splitlines():
        k, _, v = line.partition("\t")
        if k in ("ProductCode", "UpgradeCode", "ProductVersion", "ProductName", "Manufacturer"):
            props[k] = v
    return props


def gh_release(version):
    """Release metadata from the public GitHub API (no token needed), or {}."""
    try:
        data = fetch("https://api.github.com/repos/ptrinh/viettelex/releases/tags/windows-v" + version, timeout=30)
        return json.loads(data)
    except Exception:  # offline / rate-limited: the hashes we compute are authoritative anyway
        return {}


# ----------------------------------------------------------------------------- YAML out
_PLAIN = re.compile(r"^[A-Za-z0-9_./:+(),\- ]+$")
# Scalars a YAML parser would NOT read as a string (ints, floats, bools, null, dates).
_AMBIG = re.compile(r"^(?:[-+]?[0-9_]*\.?[0-9_]+(?:[eE][-+]?[0-9]+)?|[-+]?[0-9_]+\.|0x[0-9a-fA-F]+|0o?[0-7]+"
                    r"|\d{4}-\d\d-\d\d.*|\.inf|\.nan|true|false|yes|no|y|n|on|off|null|~)$", re.I)


def yscalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    s = str(v)
    if (_PLAIN.match(s) and not _AMBIG.match(s) and not s.startswith(("-", " ", ":"))
            and not s.endswith((" ", ":")) and ": " not in s and " #" not in s):
        return s
    return "'" + s.replace("'", "''") + "'"


def yaml_dump(obj, indent=0):
    pad = " " * indent
    lines = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str) and "\n" in v:
                lines.append(f"{pad}{k}: |-")
                lines += [(pad + "  " + ln) if ln else "" for ln in v.split("\n")]
            elif isinstance(v, (dict, list)):
                lines.append(f"{pad}{k}:")
                lines += yaml_dump(v, indent + 2)
            else:
                lines.append(f"{pad}{k}: {yscalar(v)}")
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                sub = yaml_dump(item, indent + 2)
                sub[0] = pad + "- " + sub[0].lstrip()
                lines += sub
            else:
                lines.append(f"{pad}- {yscalar(item)}")
    return lines


def write_manifest(path, mtype, data):
    head = [
        "# Generated by windows/installer/winget/gen_manifests.py - do not edit by hand.",
        f"# yaml-language-server: $schema=https://aka.ms/winget-manifest.{mtype}.{SCHEMA_VER}.schema.json",
        "",
    ]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(head + yaml_dump(data)) + "\n")


def reparse_yaml(path):
    """Parse the file back with an independent YAML parser (ruby stdlib), or None."""
    if not shutil.which("ruby"):
        return None
    # Dates are emitted quoted; Date is permitted only so a hand-edited unquoted
    # ReleaseDate still parses (it then shows up as a round-trip difference).
    out = subprocess.run(["ruby", "-ryaml", "-rjson", "-rdate", "-e",
                          "puts JSON.generate(YAML.safe_load(File.read(ARGV[0], encoding: 'utf-8'), "
                          "permitted_classes: [Date]))", path],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"YAML does not parse: {path}\n{out.stderr}")
    return json.loads(out.stdout)


# ----------------------------------------------------------------------------- schema
def validate(inst, schema, root, path="$", errs=None):
    """Minimal draft-07 validator for the keywords the winget schemas use."""
    if errs is None:
        errs = []
    if "$ref" in schema:
        ref = schema["$ref"]
        assert ref.startswith("#/"), ref
        node = root
        for part in ref[2:].split("/"):
            node = node[part]
        validate(inst, node, root, path, errs)
        schema = {k: v for k, v in schema.items() if k != "$ref"}
    types = schema.get("type")
    if types is not None:
        types = types if isinstance(types, list) else [types]
        ok = any({
            "string": isinstance(inst, str), "object": isinstance(inst, dict),
            "array": isinstance(inst, list), "boolean": isinstance(inst, bool),
            "integer": isinstance(inst, int) and not isinstance(inst, bool),
            "number": isinstance(inst, (int, float)) and not isinstance(inst, bool),
            "null": inst is None}[t] for t in types)
        if not ok:
            errs.append(f"{path}: type {type(inst).__name__} not in {types}")
            return errs
    if "enum" in schema and inst not in schema["enum"]:
        errs.append(f"{path}: {inst!r} not in enum")
    if "const" in schema and inst != schema["const"]:
        errs.append(f"{path}: {inst!r} != const {schema['const']!r}")
    if isinstance(inst, str):
        if "minLength" in schema and len(inst) < schema["minLength"]:
            errs.append(f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(inst) > schema["maxLength"]:
            errs.append(f"{path}: longer than {schema['maxLength']} ({len(inst)})")
        if "pattern" in schema and not re.search(schema["pattern"], inst):
            errs.append(f"{path}: {inst!r} does not match {schema['pattern']}")
    if isinstance(inst, (int, float)) and not isinstance(inst, bool):
        if "minimum" in schema and inst < schema["minimum"]:
            errs.append(f"{path}: < minimum")
        if "maximum" in schema and inst > schema["maximum"]:
            errs.append(f"{path}: > maximum")
    if isinstance(inst, list):
        if "maxItems" in schema and len(inst) > schema["maxItems"]:
            errs.append(f"{path}: more than {schema['maxItems']} items")
        if "minItems" in schema and len(inst) < schema["minItems"]:
            errs.append(f"{path}: fewer than {schema['minItems']} items")
        if schema.get("uniqueItems") and len({json.dumps(i, sort_keys=True) for i in inst}) != len(inst):
            errs.append(f"{path}: items not unique")
        if "items" in schema:
            for i, item in enumerate(inst):
                validate(item, schema["items"], root, f"{path}[{i}]", errs)
    if isinstance(inst, dict):
        props = schema.get("properties", {})
        for req in schema.get("required", []):
            if req not in inst:
                errs.append(f"{path}: missing required {req}")
        for k, v in inst.items():
            if k in props:
                validate(v, props[k], root, f"{path}.{k}", errs)
            elif props:
                errs.append(f"{path}: unknown property {k}")
    if "oneOf" in schema:
        n = sum(1 for s in schema["oneOf"] if not validate(inst, s, root, path, []))
        if n != 1:
            errs.append(f"{path}: matches {n} of oneOf")
    if "anyOf" in schema and not any(not validate(inst, s, root, path, []) for s in schema["anyOf"]):
        errs.append(f"{path}: matches none of anyOf")
    if "allOf" in schema:
        for s in schema["allOf"]:
            validate(inst, s, root, path, errs)
    if "not" in schema and not validate(inst, schema["not"], root, path, []):
        errs.append(f"{path}: matches 'not' schema")
    return errs


def check_schema(data, mtype, schema_dir):
    p = os.path.join(schema_dir, f"manifest.{mtype}.{SCHEMA_VER}.json")
    if not os.path.exists(p):
        fetch(SCHEMA_URL.format(v=SCHEMA_VER, t=mtype), p)
    with open(p, encoding="utf-8") as f:
        schema = json.load(f)
    errs = validate(data, schema, schema)  # strict: also rejects unknown keys
    try:
        import jsonschema  # optional, second opinion
        errs += [f"jsonschema: {e.message}" for e in jsonschema.Draft7Validator(schema).iter_errors(data)]
    except ImportError:
        pass
    return errs


# ----------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", help="default: docs/stable.json windows.version")
    ap.add_argument("--out", default=HERE, help="root that receives manifests/p/ptrinh/VietTelex/<V>/ (default: this folder)")
    ap.add_argument("--schema-dir", help="cache dir for the winget JSON schemas (default: temp)")
    args = ap.parse_args()

    with open(STABLE, encoding="utf-8") as f:
        win = json.load(f)["windows"]
    version = args.version or win["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit(f"bad version {version!r}")
    urls = {a: GH_ASSET.format(v=version, a=a) for a in ARCHES}
    notes = None
    if version == win["version"]:
        for a in ARCHES:
            if win[a] != urls[a]:
                raise SystemExit(f"stable.json {a} URL {win[a]} differs from the release layout {urls[a]}")
        notes = win.get("notes")

    rel = gh_release(version)
    digests = {x["name"]: (x.get("digest") or "").removeprefix("sha256:") for x in rel.get("assets", [])}
    release_date = (rel.get("published_at") or "")[:10] or None

    tmp = tempfile.mkdtemp(prefix="vtx-winget-")
    schema_dir = args.schema_dir or tmp
    os.makedirs(schema_dir, exist_ok=True)
    try:
        installers = []
        for a in ARCHES:
            msi = os.path.join(tmp, f"VietTelex-{version}-{a}.msi")
            print(f"-- downloading {urls[a]}")
            data = fetch(urls[a], msi)
            sha = hashlib.sha256(data).hexdigest().upper()
            want = digests.get(os.path.basename(msi), "")
            if want and want.upper() != sha:
                raise SystemExit(f"{a}: SHA256 {sha} != GitHub digest {want}")
            props = msi_props(msi)
            if props and props.get("ProductVersion") != version:
                raise SystemExit(f"{a}: MSI ProductVersion {props.get('ProductVersion')} != {version}")
            inst = {"Architecture": a, "InstallerUrl": urls[a], "InstallerSha256": sha}
            if props.get("ProductCode"):
                inst["ProductCode"] = props["ProductCode"]
                arp = {"DisplayName": "VietTelex", "Publisher": "VietTelex", "DisplayVersion": version,
                       "ProductCode": props["ProductCode"]}
                if props.get("UpgradeCode"):
                    arp["UpgradeCode"] = props["UpgradeCode"]
                inst["AppsAndFeaturesEntries"] = [arp]
            print(f"   {a}: sha256 {sha}  ProductCode {props.get('ProductCode', '(msiinfo unavailable: omitted)')}")
            installers.append(inst)
    finally:
        for f in os.listdir(tmp):
            if f.endswith(".msi"):
                os.remove(os.path.join(tmp, f))

    version_m = {"PackageIdentifier": PKG_ID, "PackageVersion": version, "DefaultLocale": "en-US",
                 "ManifestType": "version", "ManifestVersion": SCHEMA_VER}
    installer_m = {
        "PackageIdentifier": PKG_ID, "PackageVersion": version,
        "Platform": ["Windows.Desktop"], "MinimumOSVersion": "10.0.18362.0",
        "InstallerType": "wix", "Scope": "machine",
        "InstallModes": ["interactive", "silent", "silentWithProgress"],
        "UpgradeBehavior": "install", "ElevationRequirement": "elevatesSelf",
    }
    if release_date:
        installer_m["ReleaseDate"] = release_date
    installer_m.update({"Installers": installers, "ManifestType": "installer", "ManifestVersion": SCHEMA_VER})

    common = {"PackageIdentifier": PKG_ID, "PackageVersion": version}
    default_m = dict(common, **{
        "PackageLocale": "en-US", "Publisher": "VietTelex",
        "PublisherUrl": "https://viettelex.com", "PublisherSupportUrl": REPO + "/issues",
        "PrivacyUrl": "https://viettelex.com/privacy-policy",
        "PackageName": "VietTelex", "PackageUrl": "https://viettelex.com",
        "License": "MIT", "LicenseUrl": REPO + "/blob/main/LICENSE",
        "ShortDescription": EN["ShortDescription"], "Description": EN["Description"],
        "Moniker": "viettelex", "Tags": TAGS,
        "ReleaseNotesUrl": GH_TAG.format(v=version),
        "ManifestType": "defaultLocale", "ManifestVersion": SCHEMA_VER})
    vi_m = dict(common, **{
        "PackageLocale": "vi-VN", "Publisher": "VietTelex", "PackageName": "VietTelex",
        "PackageUrl": "https://viettelex.com", "License": "MIT",
        "ShortDescription": VI["ShortDescription"], "Description": VI["Description"], "Tags": TAGS})
    if notes:
        vi_m["ReleaseNotes"] = notes
    vi_m.update({"ReleaseNotesUrl": GH_TAG.format(v=version), "ManifestType": "locale", "ManifestVersion": SCHEMA_VER})

    outdir = os.path.join(args.out, *PKG_PATH, version)
    os.makedirs(outdir, exist_ok=True)
    files = [
        (f"{PKG_ID}.yaml", "version", version_m),
        (f"{PKG_ID}.installer.yaml", "installer", installer_m),
        (f"{PKG_ID}.locale.en-US.yaml", "defaultLocale", default_m),
        (f"{PKG_ID}.locale.vi-VN.yaml", "locale", vi_m),
    ]
    failed = False
    try:
        for name, mtype, data in files:
            path = os.path.join(outdir, name)
            write_manifest(path, mtype, data)
            errs = check_schema(data, mtype, schema_dir)
            back = reparse_yaml(path)
            if back is not None and back != data:
                errs.append("YAML round-trip differs from the generated data")
            print(f"   {'FAIL' if errs else 'ok  '} {os.path.relpath(path, ROOT)}  (schema {mtype} {SCHEMA_VER}"
                  f"{', YAML re-parsed' if back is not None else ''})")
            for e in errs:
                print("        " + e)
            failed |= bool(errs)
        # Cross-file consistency winget also enforces.
        ids = {d["PackageIdentifier"] for _, _, d in files}
        vers = {d["PackageVersion"] for _, _, d in files}
        if len(ids) != 1 or len(vers) != 1:
            print("   FAIL PackageIdentifier/PackageVersion differ between files")
            failed = True
    finally:
        shutil.rmtree(tmp, ignore_errors=True)  # MSIs already gone; schemas too unless --schema-dir
    if failed:
        raise SystemExit("manifest validation failed")
    print(f"== winget manifests for {version}: {os.path.relpath(outdir, ROOT)}")


if __name__ == "__main__":
    main()
