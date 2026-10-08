#!/usr/bin/env python3
"""Cập nhật AUR viettelex-bin (PKGBUILD + .SRCINFO) theo mục "linux" của stable.json.

    linux/packaging/aur/bump.py [--stable docs/stable.json | --stable https://viettelex.com/stable.json]
                                [--pkgrel N] [--check]

- pkgver = linux.version; checksum lấy từ linux.sha256 (cùng số với SHA256SUMS của
  GitHub Release, tên asset "~" → "."), bộ .deb noble cho x86_64 (amd64) + aarch64 (arm64).
- pkgrel: về 1 khi đổi phiên bản, giữ nguyên nếu cùng phiên bản (trừ khi --pkgrel).
- --check: không ghi, thoát 1 nếu PKGBUILD/.SRCINFO chưa khớp stable.json (dùng trong CI).

.SRCINFO được sinh ở đây (không cần makepkg); test-aur.sh so nó với
`makepkg --printsrcinfo` trong container Arch.
"""
import argparse
import json
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
PKGDIR = os.path.join(HERE, "viettelex-bin")
SERIES = "noble"
ARCH_PKGS = ("libviettelex-core", "viettelex-fcitx5", "viettelex-ibus", "viettelex-text-tools")
ARCHES = (("x86_64", "amd64"), ("aarch64", "arm64"))


def load_stable(src):
    if re.match(r"https://", src):
        with urllib.request.urlopen(src, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    with open(src, encoding="utf-8") as f:
        return json.load(f)


def sums_for(lin):
    ver = lin["version"]
    sha = lin.get("sha256") or {}

    def get(name):
        h = sha.get(name)
        if not isinstance(h, str) or not re.fullmatch(r"[0-9a-f]{64}", h):
            sys.exit("stable.json thiếu SHA256 cho %s" % name)
        return h

    common = [get("viettelex-settings_%s.%s1_all.deb" % (ver, SERIES))]
    per = {}
    for carch, darch in ARCHES:
        per[carch] = [get("%s_%s.%s1_%s.deb" % (p, ver, SERIES, darch)) for p in ARCH_PKGS]
    return common, per


def bash_array(values):
    return "(" + " ".join("'%s'" % v for v in values) + ")"


def render_pkgbuild(text, ver, rel, common, per):
    text = re.sub(r"(?m)^pkgver=.*$", "pkgver=%s" % ver, text)
    text = re.sub(r"(?m)^pkgrel=.*$", "pkgrel=%d" % rel, text)
    text = re.sub(r"(?m)^sha256sums=\(.*\)$", "sha256sums=" + bash_array(common), text)
    for carch in per:
        text = re.sub(r"(?m)^sha256sums_%s=\(.*\)$" % carch,
                      "sha256sums_%s=" % carch + bash_array(per[carch]), text)
    return text


def bash_list(text, name):
    """Giá trị mảng bash `name=( … )` (một hoặc nhiều dòng, phần tử trong nháy đơn/kép)."""
    m = re.search(r"(?ms)^%s=\((.*?)\)$" % re.escape(name), text)
    if not m:
        return []
    return [a or b for a, b in re.findall(r"'([^']*)'|\"([^\"]*)\"", m.group(1))]


def bash_scalar(text, name):
    m = re.search(r"(?m)^%s=(.*)$" % re.escape(name), text)
    return m.group(1).strip().strip("'\"") if m else None


def render_srcinfo(text):
    """Đúng thứ tự/định dạng của `makepkg --printsrcinfo` cho PKGBUILD này."""
    ver = bash_scalar(text, "pkgver")
    rel = bash_scalar(text, "pkgrel")
    series = bash_scalar(text, "_series")
    gh = "https://github.com/ptrinh/viettelex/releases/download/linux-v%s" % ver

    def expand(s):
        return (s.replace("${_gh}", gh).replace("${pkgver}", ver).replace("${_series}", series))

    name = bash_scalar(text, "pkgname")
    lines = ["pkgbase = %s" % name,
             "\tpkgdesc = %s" % bash_scalar(text, "pkgdesc"),
             "\tpkgver = %s" % ver,
             "\tpkgrel = %s" % rel,
             "\turl = %s" % bash_scalar(text, "url"),
             "\tinstall = %s" % bash_scalar(text, "install")]
    lines += ["\tarch = %s" % a for a in bash_list(text, "arch")]
    lines += ["\tlicense = %s" % a for a in bash_list(text, "license")]
    lines += ["\tdepends = %s" % a for a in bash_list(text, "depends")]
    lines += ["\toptdepends = %s" % a for a in bash_list(text, "optdepends")]
    lines += ["\tprovides = %s" % a for a in bash_list(text, "provides")]
    lines += ["\tconflicts = %s" % a for a in bash_list(text, "conflicts")]
    noext = [os.path.basename(expand(s)) for k in ("source", "source_x86_64", "source_aarch64")
             for s in bash_list(text, k)]
    lines += ["\tnoextract = %s" % n for n in noext]
    lines += ["\toptions = %s" % o for o in bash_list(text, "options")]
    lines += ["\tsource = %s" % expand(s) for s in bash_list(text, "source")]
    lines += ["\tsha256sums = %s" % s for s in bash_list(text, "sha256sums")]
    for carch, _ in ARCHES:
        lines += ["\tsource_%s = %s" % (carch, expand(s)) for s in bash_list(text, "source_" + carch)]
        lines += ["\tsha256sums_%s = %s" % (carch, s) for s in bash_list(text, "sha256sums_" + carch)]
    lines += ["", "pkgname = %s" % name]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stable", default=os.path.join(REPO, "docs", "stable.json"))
    ap.add_argument("--pkgrel", type=int, default=None)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    lin = load_stable(a.stable).get("linux")
    if not isinstance(lin, dict) or SERIES not in (lin.get("series") or []):
        sys.exit("stable.json không có mục linux với series %s" % SERIES)
    ver = lin["version"]
    common, per = sums_for(lin)

    pkgbuild = os.path.join(PKGDIR, "PKGBUILD")
    old = open(pkgbuild, encoding="utf-8").read()
    old_ver = bash_scalar(old, "pkgver")
    rel = a.pkgrel if a.pkgrel is not None else (int(bash_scalar(old, "pkgrel")) if old_ver == ver else 1)
    new = render_pkgbuild(old, ver, rel, common, per)
    srcinfo = render_srcinfo(new)
    srcinfo_path = os.path.join(PKGDIR, ".SRCINFO")
    old_srcinfo = open(srcinfo_path, encoding="utf-8").read() if os.path.exists(srcinfo_path) else ""

    if a.check:
        if new != old or srcinfo != old_srcinfo:
            sys.exit("AUR viettelex-bin chưa khớp stable.json (%s) — chạy linux/packaging/aur/bump.py" % ver)
        print("AUR viettelex-bin khớp stable.json (%s-%d)" % (ver, rel))
        return
    with open(pkgbuild, "w", encoding="utf-8") as f:
        f.write(new)
    with open(srcinfo_path, "w", encoding="utf-8") as f:
        f.write(srcinfo)
    print("viettelex-bin → %s-%d (%s)" % (ver, rel, "đổi" if new != old else "không đổi"))


if __name__ == "__main__":
    main()
