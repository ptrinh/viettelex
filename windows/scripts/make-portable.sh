#!/usr/bin/env bash
# Portable zips (docs/WINDOWS-APP-FEEL-SPEC.md "Bản portable") from already-built (and, in a
# release, already-signed) VietTelex.exe files:
#
#   windows/scripts/make-portable.sh <version> <bin-dir> <out-dir>
#
#   <bin-dir>/{x64,arm64}/VietTelex.exe  ->  <out-dir>/VietTelex-<version>-portable-{x64,arm64}.zip
#
# Each zip holds one folder VietTelex-<version>-portable-<arch>/ with VietTelex.exe, the
# portable.ini marker (core/portable.h: the exe runs in portable mode when it sits next to
# it) and a short README.txt. Deterministic: fixed file order and timestamps, no extra
# attributes, so the same input gives the same bytes. release.sh calls it after signing
# the binaries; app/tests runs it on dummy files (portable_zip_test.sh).
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: $0 <version> <bin-dir> <out-dir>" >&2; exit 2; }
VERSION="$1" BIN="$2" OUT="$3"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be X.Y.Z" >&2; exit 2; }
command -v zip >/dev/null 2>&1 || { echo "missing tool: zip" >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

for arch in x64 arm64; do
  exe="$BIN/$arch/VietTelex.exe"
  [ -f "$exe" ] || { echo "missing $exe" >&2; exit 1; }
  name="VietTelex-$VERSION-portable-$arch"
  work="$(mktemp -d)"
  mkdir "$work/$name"
  cp "$exe" "$work/$name/VietTelex.exe"
  # CRLF text files: they are opened with Notepad.
  printf '%s\r\n' \
    "; VietTelex portable — keep this file next to VietTelex.exe." \
    "; Its presence makes VietTelex run in portable mode: settings are saved in settings.ini" \
    "; in this folder, nothing is installed and Windows' keyboard list is never changed." \
    "[VietTelex]" \
    "portable=1" > "$work/$name/portable.ini"
  printf '%s\r\n' \
    "VietTelex $VERSION — bản portable ($arch)" \
    "" \
    "Cách dùng: giải nén cả thư mục (chuột phải file zip -> Giải nén tất cả) rồi chạy VietTelex.exe" \
    "trong thư mục đã giải nén — đừng chạy thẳng từ trong file zip. Không cần quyền quản trị, không cài gì." \
    "Biểu tượng V/E hiện ở khay; đổi Việt/Anh bằng Ctrl+Shift hoặc bấm vào biểu tượng." \
    "Bản portable KHÔNG có trong danh sách bàn phím của Windows (Win+Space): cứ để bàn phím tiếng Anh," \
    "VietTelex gõ tiếng Việt trên đó. Khi đang chọn một bàn phím tiếng Việt, bản portable nhường." \
    "Cài đặt lưu trong settings.ini cạnh VietTelex.exe. Xoá thư mục là gỡ xong." \
    "" \
    "Máy đã cài VietTelex (.msi) và bản cài đang chạy: bản portable báo rồi thoát. Muốn dùng bản portable," \
    "bấm chuột phải biểu tượng VietTelex ở khay -> Thoát VietTelex trước, rồi mới chạy bản portable." \
    "" \
    "Khác bản cài (.msi): gõ bằng hook bàn phím cho mọi ứng dụng, nên trình duyệt/Word không mượt bằng;" \
    "không gõ được vào ứng dụng chạy quyền quản trị và một số game. Không tự cập nhật: \"Kiểm tra cập nhật\"" \
    "mở trang tải." \
    "" \
    "VietTelex $VERSION — portable ($arch)" \
    "" \
    "Unzip the whole folder (right-click the zip -> Extract All) and run VietTelex.exe from the extracted" \
    "folder — not from inside the zip. No administrator rights, nothing is installed." \
    "A V/E icon appears in the notification area; switch Vietnamese/English with Ctrl+Shift or a click on it." \
    "The portable copy is NOT in Windows' keyboard list (Win+Space): keep an English keyboard selected and" \
    "VietTelex types Vietnamese on it. While a Vietnamese keyboard is selected, the portable copy steps aside." \
    "Settings are saved in settings.ini next to VietTelex.exe. Delete the folder to remove it." \
    "" \
    "If the installed VietTelex (.msi) is running, the portable copy says so and quits. To use the portable" \
    "copy, right-click the VietTelex tray icon -> Quit VietTelex first, then start the portable copy." \
    "" \
    "Unlike the installer (.msi) it types with a keyboard hook in every app, so browsers/Word are less smooth;" \
    "it cannot type into apps running as administrator or some games. No self-update: \"Check for updates\"" \
    "opens the download page." \
    "" \
    "https://viettelex.com/download/?os=windows#portable" > "$work/$name/README.txt"
  touch -t 202601010000 "$work/$name" "$work/$name/"*
  zip="$OUT/$name.zip"
  rm -f "$zip"
  ( cd "$work" && zip -q -X -D "$zip" "$name/VietTelex.exe" "$name/portable.ini" "$name/README.txt" )
  rm -rf "$work"
  echo "  portable $(basename "$zip")"
done
