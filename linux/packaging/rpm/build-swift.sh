#!/bin/bash
# Chạy TRONG ảnh swift:rhel-ubi9 (toolchain Swift chính thức, glibc 2.34): build engine
# libtelexcore.so + viettelex-text-tool đúng như CMake của gói (target telexcore_swift:
# SwiftPM --static-swift-stdlib + FoundationEssentials tĩnh), rồi chép ra --out.
# glibc 2.34 là mức thấp nhất trong các distro RPM hỗ trợ (EL9) ⇒ một bản dùng cho cả
# EL9, EL10 và Fedora. Gọi bởi linux/packaging/build-rpm.sh.
#
#   build-swift.sh --out /out
set -euo pipefail
OUT=/out
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
echo "==> $(swift --version 2>&1 | head -1) ($(uname -m))"
# Chỉ cần cấu hình CMake (gio-2.0 là REQUIRED ở linux/CMakeLists.txt); frontend không build ở đây.
dnf -y -q install cmake gcc-c++ make glib2-devel pkgconf-pkg-config >/dev/null
W=$(mktemp -d)
# /src chỉ đọc ⇒ dàn bản sao ghi được (symlink tương đối giữa linux/ ↔ TelexCore/ ↔ iOS/ giữ nguyên).
S=$(mktemp -d)
( cd /src && tar -cf - --exclude='.build' --exclude='.swiftpm' --exclude='linux/dist' \
    TelexCore linux iOS/Keyboard iOS/KeyboardTests/Fixtures \
    App/Sources/SeedNextData.swift App/Sources/LearnedModel.swift \
    App/Sources/LunarCalendar.swift ) | tar -xf - -C "$S"
cmake -S "$S/linux" -B "$W" -DVT_BUILD_FCITX5=OFF -DVT_BUILD_IBUS=OFF -DVT_BUILD_TESTS=OFF >"$W.log" 2>&1 \
  || { tail -30 "$W.log"; exit 1; }
cmake --build "$W" --target telexcore_swift >>"$W.log" 2>&1 || { tail -40 "$W.log"; exit 1; }
mkdir -p "$OUT"
install -m755 "$W/swift/release/libtelexcore.so" "$W/swift/release/viettelex-text-tool" "$OUT/"
# Không được kéo thư viện Swift động (static stdlib) — chỉ glibc/libstdc++/libgcc_s.
if ldd "$OUT/libtelexcore.so" "$OUT/viettelex-text-tool" | grep -E "libswift|libFoundation|not found"; then
  echo "✗ engine còn phụ thuộc thư viện Swift động" >&2; exit 1
fi
printf 'toi di hoc' | VIETTELEX_DATA_DIR="$S"/iOS/Keyboard/Resources "$OUT/viettelex-text-tool" addTones; echo
ls -l "$OUT"
