#!/usr/bin/env bash
# ctest: scripts/make-portable.sh on dummy exes — zip names, contents, the portable.ini
# marker core/portable.h looks for, determinism, and that release.sh lists the zips in
# SHA256SUMS. Usage: portable_zip_test.sh <windows-dir> <scratch-dir>
set -euo pipefail
WIN="$1" T="$2/portable-zip-test"
rm -rf "$T"
mkdir -p "$T/bin/x64" "$T/bin/arm64"
printf 'MZx64' > "$T/bin/x64/VietTelex.exe"
printf 'MZarm64' > "$T/bin/arm64/VietTelex.exe"
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$WIN/scripts/make-portable.sh" 9.8.7 "$T/bin" "$T/out" >/dev/null
for arch in x64 arm64; do
  z="$T/out/VietTelex-9.8.7-portable-$arch.zip"
  [ -f "$z" ] || fail "no $z"
  list="$(unzip -Z1 "$z")"
  want="VietTelex-9.8.7-portable-$arch/VietTelex.exe
VietTelex-9.8.7-portable-$arch/portable.ini
VietTelex-9.8.7-portable-$arch/README.txt"
  [ "$list" = "$want" ] || fail "zip $arch lists: $list"
  [ "$(unzip -p "$z" "VietTelex-9.8.7-portable-$arch/VietTelex.exe")" = "MZ$arch" ] || fail "wrong exe in $arch zip"
  unzip -p "$z" "VietTelex-9.8.7-portable-$arch/portable.ini" | grep -q '^\[VietTelex\]' || fail "marker content"
  unzip -p "$z" "VietTelex-9.8.7-portable-$arch/README.txt" | grep -q 'portable' || fail "readme"
done
# Deterministic: same input, same bytes.
cp "$T/out/VietTelex-9.8.7-portable-x64.zip" "$T/first.zip"
sleep 1
bash "$WIN/scripts/make-portable.sh" 9.8.7 "$T/bin" "$T/out" >/dev/null
cmp -s "$T/first.zip" "$T/out/VietTelex-9.8.7-portable-x64.zip" || fail "zip is not deterministic"
# Bad input is refused.
if bash "$WIN/scripts/make-portable.sh" 9.8 "$T/bin" "$T/out" 2>/dev/null; then fail "accepted a bad version"; fi
rm "$T/bin/arm64/VietTelex.exe"
if bash "$WIN/scripts/make-portable.sh" 9.8.7 "$T/bin" "$T/out2" 2>/dev/null; then fail "accepted a missing exe"; fi
# release.sh wires it in: called after signing, zips in SHA256SUMS, in the publish checklist.
r="$WIN/scripts/release.sh"
grep -q 'make-portable.sh' "$r" || fail "release.sh does not build the portable zips"
grep -q "\*.zip" "$r" || fail "release.sh SHA256SUMS misses the zips"
grep -q 'portable-x64.zip' "$r" || fail "publish checklist misses the zips"
# The marker name matches core/portable.h.
grep -q 'L"portable.ini"' "$WIN/app/core/portable.h" || fail "marker name drifted from core/portable.h"
rm -rf "$T"
echo "portable zip test: ok"
