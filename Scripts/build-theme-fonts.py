#!/usr/bin/env python3
"""Dựng bộ font tải về cho theme bàn phím (iOS + Android).

Nguồn: repo google/fonts (thư mục ofl/<family>/), ghim theo commit SOURCE_SHA.
Mỗi font: 1 độ đậm (400, hoặc 500 với họ nét mảnh) → instance tĩnh (nếu là
variable font) → subset Latin + tiếng Việt, bỏ hinting → kiểm đủ chữ Việt
dựng sẵn → đổi tên nếu OFL có Reserved Font Name trùng tên họ.

Đầu ra (đường dẫn tính từ gốc repo):
  docs/fonts/<Stem>.ttf, docs/fonts/OFL-<Stem>.txt, docs/fonts/manifest.json
      (docs/ là GitHub Pages → https://viettelex.com/fonts/<file>)
  themes/builtin-fonts.json          (app nhúng nguyên văn: cấm $, \\, ba dấu ")
  iOS/App/FontPreviews/<id>.ttf      (font xem trước: chỉ "V", "t")
  android/app/src/main/assets/fontpreview/<id_gạch_dưới>.ttf

Phông NHÚNG (BUNDLED — không tải qua URL, nạp lười khi theme dùng: KeyLabelFont "pixel"):
  fonts/<Stem>.ttf, fonts/OFL-<Stem>.txt  (iOS: project.yml chép vào bàn phím + test;
      Android: app/build.gradle.kts thêm fonts/ vào assets) — tối đa BUNDLED_MAX_BYTES, đủ chữ Việt.

Cách chạy:
  python3 -I Scripts/build-theme-fonts.py --download /tmp/fonts-src   # tải nguồn
  python3 -I Scripts/build-theme-fonts.py /tmp/fonts-src              # dựng
  python3 -I Scripts/build-theme-fonts.py --bundled-only /tmp/fonts-src   # chỉ dựng phông nhúng
  python3 -I Scripts/build-theme-fonts.py --check                     # kiểm phông nhúng đủ chữ Việt
Thư mục nguồn có dạng <src>/<family>/<file nguồn> + <src>/<family>/OFL.txt.
Cần fontTools (pip install fonttools).
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys
import urllib.parse
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SOURCE_SHA = "47d54ca1ebb14fd864695f1d39dc734f39017c33"
RAW_BASE = "https://raw.githubusercontent.com/google/fonts/" + SOURCE_SHA + "/ofl/"
URL_BASE = "https://viettelex.com/fonts/"
RENAME_PREFIX = "VT "

# (id, tên hiển thị gốc, thư mục google/fonts, file nguồn, stem đầu ra, độ đậm)
# 500 (Medium) cho họ nét mảnh ở cỡ nhãn phím: Be Vietnam Pro, Quicksand, Dancing Script.
FONTS = [
    ("be-vietnam-pro", "Be Vietnam Pro", "bevietnampro", "BeVietnamPro-Medium.ttf", "BeVietnamPro-Medium", 500),
    ("nunito", "Nunito", "nunito", "Nunito[wght].ttf", "Nunito-Regular", 400),
    ("quicksand", "Quicksand", "quicksand", "Quicksand[wght].ttf", "Quicksand-Medium", 500),
    ("baloo-2", "Baloo 2", "baloo2", "Baloo2[wght].ttf", "Baloo2-Regular", 400),
    ("pacifico", "Pacifico", "pacifico", "Pacifico-Regular.ttf", "Pacifico-Regular", 400),
    ("dancing-script", "Dancing Script", "dancingscript", "DancingScript[wght].ttf", "DancingScript-Medium", 500),
    ("lobster", "Lobster", "lobster", "Lobster-Regular.ttf", "Lobster-Regular", 400),
    ("patrick-hand", "Patrick Hand", "patrickhand", "PatrickHand-Regular.ttf", "PatrickHand-Regular", 400),
    ("itim", "Itim", "itim", "Itim-Regular.ttf", "Itim-Regular", 400),
    ("playfair-display", "Playfair Display", "playfairdisplay", "PlayfairDisplay[wght].ttf", "PlayfairDisplay-Regular", 400),
    ("lexend", "Lexend", "lexend", "Lexend[wght].ttf", "Lexend-Regular", 400),
    ("montserrat", "Montserrat", "montserrat", "Montserrat[wght].ttf", "Montserrat-Regular", 400),
    # Phông máy chữ cho theme "Máy chữ cổ" (typewriter): đơn cách có chân, đủ chữ Việt (Courier Prime thiếu ơ/ư/ạ…).
    ("xanh-mono", "Xanh Mono", "xanhmono", "XanhMono-Regular.ttf", "XanhMono-Regular", 400),
]

# Phông NHÚNG trong app (cùng bộ cột như FONTS; id = KeyLabelFont rawValue). Theme "Pixel 8-bit" ("font":"pixel"):
# Tiny5 — phông điểm ảnh 5 px khối vuông kiểu máy 8-bit, đủ chữ Việt dựng sẵn (Pixelify Sans thiếu ơ/ư/ạ…). OFL của
# Tiny5 KHÔNG khai báo Reserved Font Name ⇒ bản subset được giữ tên (luật đổi tên ở dưới vẫn chạy nếu sau này có).
BUNDLED = [
    ("pixel", "Tiny5", "tiny5", "Tiny5[BLED,JITT,ROND,wdth,wght].ttf", "Tiny5-Regular", 400),
]
BUNDLED_MAX_BYTES = 60 * 1024

UNICODES = (
    "U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,"
    "U+0102-0103,U+0110-0111,U+0128-0129,U+0168-0169,U+01A0-01A1,U+01AF-01B0,"
    "U+0300-0301,U+0303-0304,U+0308-0309,U+0323,U+0329,U+1EA0-1EF9,"
    "U+2000-206F,U+20AB,U+20AC,U+2122,U+2212,U+FEFF,U+FFFD"
)

# Mọi chữ cái tiếng Việt dựng sẵn phải có trong cmap.
VI_REQUIRED = set(range(0x1EA0, 0x1EFA)) | {ord(c) for c in (
    "ĂăÂâĐđÊêÔôƠơƯưĨĩŨũ"
    "àáãèéêìíòóõùúýÀÁÃÈÉÌÍÒÓÕÙÚÝ"
    "ỳỷỹỵ"
)}

WEIGHT_NAME = {400: "Regular", 500: "Medium"}


def parse_unicodes(spec):
    out = []
    for part in spec.split(","):
        part = part.strip().replace("U+", "")
        if "-" in part:
            a, b = part.split("-")
            out.extend(range(int(a, 16), int(b, 16) + 1))
        else:
            out.append(int(part, 16))
    return out


def reserved_font_names(ofl_text):
    """RFN khai báo ở phần copyright (trước câu 'This Font Software is licensed')."""
    header = ofl_text.split("This Font Software is licensed")[0]
    names = []
    for m in re.finditer(r"Reserved Font Names?\s+(.+?)(?:\.\s|\n|$)", header, re.S):
        names += re.findall(r"[\"'“”‘’]([^\"'“”‘’]+)[\"'“”‘’]", m.group(1))
    return names


def download(dest):
    for _id, _name, fam, src, _stem, _w in FONTS + BUNDLED:
        d = os.path.join(dest, fam)
        os.makedirs(d, exist_ok=True)
        for name in (src, "OFL.txt"):
            data = urllib.request.urlopen(RAW_BASE + fam + "/" + urllib.parse.quote(name)).read()
            with open(os.path.join(d, name), "wb") as f:
                f.write(data)
            print("tải", fam, name, len(data))


def static_instance(font, weight):
    """Variable → static ở wght=weight, các trục khác ghim về mặc định."""
    if "fvar" not in font:
        cur = font["OS/2"].usWeightClass
        if cur != weight:
            sys.exit(f"font tĩnh có weight {cur}, cần {weight}")
        return font
    limits = {a.axisTag: a.defaultValue for a in font["fvar"].axes}
    limits["wght"] = weight
    font = instancer.instantiateVariableFont(font, limits, inplace=False)
    for t in ("STAT", "fvar", "avar"):
        if t in font:
            del font[t]
    font["OS/2"].usWeightClass = weight
    return font


def set_names(font, family, weight):
    """Ghi lại bảng name gọn (ID 1-6, + 16/17 nếu là Medium)."""
    style = WEIGHT_NAME[weight]
    name = font["name"]
    version = name.getDebugName(5) or "Version 1.000"
    copyright_ = name.getDebugName(0) or ""
    ps = re.sub(r"[^A-Za-z0-9]", "", family) + "-" + style
    full = family if style == "Regular" else f"{family} {style}"
    name.names = []
    recs = {
        0: copyright_,
        1: family if style == "Regular" else full,
        2: "Regular",
        3: f"{version.replace('Version ', '')};VietTelex subset;{ps}",
        4: full,
        5: version,
        6: ps,
    }
    if style != "Regular":
        recs[16] = family
        recs[17] = style
    for nid, s in recs.items():
        name.setName(s, nid, 3, 1, 0x409)
    font["OS/2"].usWeightClass = weight
    font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~0b1100001) | 0b1000000  # REGULAR
    font["head"].macStyle = 0


def do_subset(font, unicodes, layout=True):
    opts = subset.Options()
    opts.hinting = False
    opts.desubroutinize = True
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    opts.name_languages = [0x409]
    opts.glyph_names = False
    opts.drop_tables += ["DSIG", "hdmx", "VDMX", "LTSH", "kerx", "morx", "STAT", "fvar", "avar", "meta"]
    if layout:
        opts.layout_features = subset.Options().layout_features  # bộ mặc định: kern, mark, mkmk, ccmp, locl, liga…
    else:
        opts.layout_features = []
        opts.drop_tables += ["GSUB", "GPOS", "GDEF", "kern"]
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=unicodes)
    sub.subset(font)
    return font


def to_bytes(font):
    font.recalcTimestamp = False  # giữ head.modified của nguồn → chạy lại ra cùng sha256
    buf = io.BytesIO()
    font.save(buf)
    return buf.getvalue()


def bundled_issues(data):
    """Lỗi của một phông nhúng (rỗng = đạt): thiếu chữ Việt dựng sẵn / quá cỡ."""
    out = []
    missing = sorted(VI_REQUIRED - set(TTFont(io.BytesIO(data)).getBestCmap()))
    if missing:
        out.append("THIẾU " + " ".join(f"U+{c:04X}" for c in missing))
    if len(data) > BUNDLED_MAX_BYTES:
        out.append(f"{len(data)} B > {BUNDLED_MAX_BYTES} B")
    return out


def build_bundled(src, root):
    out_dir = os.path.join(root, "fonts")
    os.makedirs(out_dir, exist_ok=True)
    unicodes = parse_unicodes(UNICODES)
    for fid, display, fam, file, stem, weight in BUNDLED:
        ofl_bytes = open(os.path.join(src, fam, "OFL.txt"), "rb").read()
        rfns = reserved_font_names(ofl_bytes.decode("utf-8-sig"))
        renamed = any(r.lower() in display.lower() for r in rfns)
        family = RENAME_PREFIX + display if renamed else display
        font = static_instance(TTFont(os.path.join(src, fam, file)), weight)
        font = do_subset(TTFont(io.BytesIO(to_bytes(font))), unicodes)
        set_names(font, family, weight)
        data = to_bytes(font)
        issues = bundled_issues(data)
        if issues:
            sys.exit(f"phông nhúng {fid}: " + "; ".join(issues))
        with open(os.path.join(out_dir, stem + ".ttf"), "wb") as f:
            f.write(data)
        with open(os.path.join(out_dir, f"OFL-{stem}.txt"), "wb") as f:
            f.write(ofl_bytes)  # nguyên văn
        print(f"nhúng {fid:10} {stem}.ttf {len(data):7} B  RFN={rfns or '-'} renamed={renamed}  "
              f"sha256={hashlib.sha256(data).hexdigest()}")
    note = ("Phông NHÚNG trong app (không tải qua mạng) — subset Latin + tiếng Việt của phông OFL-1.1,\n"
            "giấy phép nguyên văn: OFL-<tên>.txt cạnh tệp phông. Sinh bởi Scripts/build-theme-fonts.py\n"
            "(--bundled-only); kiểm: --check. iOS: project.yml (bàn phím + test); Android: app/build.gradle.kts\n"
            "(assets). Nạp lười CHỈ khi theme dùng (KeyLabelFont \"pixel\").\n")
    for fid, display, fam, file, stem, weight in BUNDLED:
        note += f"  {stem}.ttf — {display} (id \"{fid}\"), nguồn github.com/google/fonts@{SOURCE_SHA} ofl/{fam}/{file}\n"
    with open(os.path.join(out_dir, "README.txt"), "w", encoding="utf-8") as f:
        f.write(note)


def check_bundled(root):
    bad = []
    for fid, _display, _fam, _file, stem, _w in BUNDLED:
        p = os.path.join(root, "fonts", stem + ".ttf")
        lic = os.path.join(root, "fonts", f"OFL-{stem}.txt")
        issues = bundled_issues(open(p, "rb").read()) if os.path.exists(p) else ["không có tệp"]
        if not os.path.exists(lic):
            issues.append("thiếu giấy phép OFL")
        print(f"{fid:10} {stem}.ttf: " + ("OK" if not issues else "; ".join(issues)))
        if issues:
            bad.append(fid)
    if bad:
        sys.exit("phông nhúng lỗi: " + ", ".join(bad))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?", help="thư mục nguồn <src>/<family>/...")
    ap.add_argument("--download", action="store_true", help="tải nguồn về src rồi thoát")
    ap.add_argument("--bundled-only", action="store_true", help="chỉ dựng phông nhúng (fonts/)")
    ap.add_argument("--check", action="store_true", help="kiểm phông nhúng trong fonts/ (đủ chữ Việt, cỡ)")
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if args.check:
        check_bundled(root)
        return
    if not args.src:
        ap.error("thiếu thư mục nguồn")
    if args.download:
        download(args.src)
        return
    build_bundled(args.src, root)
    if args.bundled_only:
        return

    out_docs = os.path.join(root, "docs", "fonts")
    out_ios = os.path.join(root, "iOS", "App", "FontPreviews")
    out_and = os.path.join(root, "android", "app", "src", "main", "assets", "fontpreview")
    for d in (out_docs, out_ios, out_and):
        os.makedirs(d, exist_ok=True)

    unicodes = parse_unicodes(UNICODES)
    manifest = []
    failed = []
    for fid, display, fam, src, stem, weight in FONTS:
        assert re.fullmatch(r"[a-z0-9-]+", fid) and re.fullmatch(r"[A-Za-z0-9-]+", stem)
        ofl_bytes = open(os.path.join(args.src, fam, "OFL.txt"), "rb").read()
        ofl = ofl_bytes.decode("utf-8-sig")
        rfns = reserved_font_names(ofl)
        renamed = any(r.lower() in display.lower() for r in rfns)
        family = RENAME_PREFIX + display if renamed else display

        base = static_instance(TTFont(os.path.join(args.src, fam, src)), weight)
        base_bytes = to_bytes(base)

        # Font đầy đủ (Latin + Việt).
        font = do_subset(TTFont(io.BytesIO(base_bytes)), unicodes)
        set_names(font, family, weight)
        data = to_bytes(font)
        cmap = TTFont(io.BytesIO(data)).getBestCmap()
        missing = sorted(VI_REQUIRED - set(cmap))
        status = "OK" if not missing else "THIẾU " + " ".join(f"U+{c:04X}" for c in missing)
        if missing:
            failed.append(fid)
        file = stem + ".ttf"
        with open(os.path.join(out_docs, file), "wb") as f:
            f.write(data)
        with open(os.path.join(out_docs, f"OFL-{stem}.txt"), "wb") as f:
            f.write(ofl_bytes)  # nguyên văn

        # Font xem trước: chỉ "V", "t" (+ .notdef).
        prev = do_subset(TTFont(io.BytesIO(base_bytes)), [ord("V"), ord("t")], layout=False)
        set_names(prev, family, weight)
        pdata = to_bytes(prev)
        with open(os.path.join(out_ios, fid + ".ttf"), "wb") as f:
            f.write(pdata)
        with open(os.path.join(out_and, fid.replace("-", "_") + ".ttf"), "wb") as f:
            f.write(pdata)

        print(f"{fid:18} {file:28} {len(data):7} B  xem trước {len(pdata):5} B  "
              f"RFN={rfns or '-'} renamed={renamed}  tiếng Việt: {status}")
        manifest.append({
            "id": fid,
            "name": family,
            "file": file,
            "url": URL_BASE + file,
            "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data),
            "weight": weight,
            "license": "OFL-1.1",
            "licenseFile": f"OFL-{stem}.txt",
            "renamed": renamed,
        })

    if failed:
        sys.exit("thiếu chữ Việt: " + ", ".join(failed))

    with open(os.path.join(out_docs, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"v": 1, "source": "github.com/google/fonts@" + SOURCE_SHA, "fonts": manifest},
                  f, indent=2, ensure_ascii=False)
        f.write("\n")

    builtin = {"v": 1, "fonts": [{k: m[k] for k in ("id", "name", "url", "sha256", "bytes")} for m in manifest]}
    text = json.dumps(builtin, indent=2, ensure_ascii=False) + "\n"
    assert "$" not in text and "\\" not in text and '"""' not in text
    with open(os.path.join(root, "themes", "builtin-fonts.json"), "w", encoding="utf-8") as f:
        f.write(text)

    note = ("Font xem trước (chỉ glyph \"V\", \"t\") — subset của các font OFL-1.1 liệt kê trong\n"
            "docs/fonts/manifest.json; giấy phép từng font: docs/fonts/OFL-*.txt.\n"
            "Sinh bởi Scripts/build-theme-fonts.py.\n")
    for d in (out_ios, out_and):
        with open(os.path.join(d, "README.txt"), "w", encoding="utf-8") as f:
            f.write(note)


if __name__ == "__main__":
    main()
