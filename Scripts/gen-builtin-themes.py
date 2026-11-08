#!/usr/bin/env python3
"""Sinh dữ liệu theme có sẵn cho iOS + Android từ MỘT nguồn: themes/builtin-themes.json.

Chuỗi JSON được nhúng NGUYÊN VĂN (iOS: Keyboard/BuiltinThemes.swift, Android:
keyboard/.../BuiltinThemesData.kt) — hai bên parse bằng cùng bộ đọc chặt (ThemeSpec), test hai
bên kiểm tra chuỗi nhúng trùng file nguồn. Sửa theme: sửa file JSON rồi chạy lại script này.

  python3 Scripts/gen-builtin-themes.py          # ghi lại hai file
  python3 Scripts/gen-builtin-themes.py --check  # chỉ kiểm tra (exit 1 nếu lệch)
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "themes", "builtin-themes.json")
SWIFT = os.path.join(ROOT, "iOS", "Keyboard", "BuiltinThemes.swift")
KOTLIN = os.path.join(ROOT, "android", "keyboard", "src", "main", "kotlin", "com", "viettelex", "keyboard",
                      "BuiltinThemesData.kt")

FONTS_SRC = os.path.join(ROOT, "themes", "builtin-fonts.json")
FONTS_SWIFT = os.path.join(ROOT, "iOS", "Keyboard", "BuiltinFonts.swift")
FONTS_KOTLIN = os.path.join(ROOT, "android", "keyboard", "src", "main", "kotlin", "com", "viettelex", "keyboard",
                            "BuiltinFontsData.kt")

HEADER = "Sinh bởi Scripts/gen-builtin-themes.py từ themes/builtin-themes.json — KHÔNG sửa tay."


def main():
    text = open(SRC, encoding="utf-8").read()
    json.loads(text)  # phải là JSON hợp lệ
    for bad in ('"""', "$", "\\"):
        if bad in text:
            sys.exit(f"builtin-themes.json không được chứa {bad!r} (nhúng chuỗi thô)")
    swift = (f"// {HEADER}\n"
             "// Theme có sẵn (trừ Hệ thống / Kính — vẽ theo nền tảng) dạng JSON, đọc một lần (BuiltinThemes.specs).\n"
             "enum BuiltinThemesData {\n"
             f'    static let json = ##"""\n{text.rstrip(chr(10))}\n"""##\n'
             "}\n")
    kotlin = (f"// {HEADER}\n"
              "package com.viettelex.keyboard\n\n"
              "/** Theme có sẵn (trừ Hệ thống / Kính — vẽ theo nền tảng) dạng JSON, đọc một lần ([BuiltinThemes]). */\n"
              "internal object BuiltinThemesData {\n"
              f'    const val JSON = """\n{text.rstrip(chr(10))}\n"""\n'
              "}\n")
    ftext = open(FONTS_SRC, encoding="utf-8").read()
    json.loads(ftext)
    for bad in ('"""', "$", "\\"):
        if bad in ftext:
            sys.exit(f"builtin-fonts.json không được chứa {bad!r} (nhúng chuỗi thô)")
    fh = "Sinh bởi Scripts/gen-builtin-themes.py từ themes/builtin-fonts.json — KHÔNG sửa tay."
    fswift = (f"// {fh}\n"
              "// Phông tải về có sẵn (OFL, host viettelex.com/fonts kèm sha256) — lưới chọn phông (BuiltinFonts.list).\n"
              "enum BuiltinFontsData {\n"
              f'    static let json = ##"""\n{ftext.rstrip(chr(10))}\n"""##\n'
              "}\n")
    fkotlin = (f"// {fh}\n"
               "package com.viettelex.keyboard\n\n"
               "/** Phông tải về có sẵn (OFL, host viettelex.com/fonts kèm sha256) — lưới chọn phông ([BuiltinFonts]). */\n"
               "internal object BuiltinFontsData {\n"
               f'    const val JSON = """\n{ftext.rstrip(chr(10))}\n"""\n'
               "}\n")
    check = "--check" in sys.argv
    stale = []
    for path, content in ((SWIFT, swift), (KOTLIN, kotlin), (FONTS_SWIFT, fswift), (FONTS_KOTLIN, fkotlin)):
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if old != content:
            stale.append(path)
            if not check:
                open(path, "w", encoding="utf-8").write(content)
    if check and stale:
        sys.exit("lệch nguồn: " + ", ".join(stale))
    print("ok" if not stale else "đã ghi: " + ", ".join(os.path.relpath(p, ROOT) for p in stale))


if __name__ == "__main__":
    main()
