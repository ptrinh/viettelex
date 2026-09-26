#!/bin/sh
# Regression test for the 1.0.0 install failure on Windows ("Error 2211: Could not create
# database table Registry" at FileCost, then 1603).
#
#   check_msi_test.sh <vtx_regtable>
#
# Builds the real template (viettelex.wxs.in, dummy payload) two ways:
#   1.0.0 way: registry rows added after wixl with msibuild SQL INSERT  -> must FAIL
#   now:       registry rows spliced into the .wxs and written by wixl  -> must PASS
# check_msi.py has to tell them apart. Wine and libmsi install both, so the difference is
# only visible in the table bytes (rows out of primary-key order).
# Needs wixl + msibuild (msitools); skipped (exit 0) without them.
set -eu
REGTABLE="$1"
here="$(cd "$(dirname "$0")" && pwd)"
command -v wixl >/dev/null 2>&1 && command -v msibuild >/dev/null 2>&1 || { echo "skip: msitools absent"; exit 0; }
d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
for f in VietTelex.exe VietTelexTIP.dll; do echo "$f" > "$d/$f"; done
fill() {
  sed -e "s|@VERSION@|1.0.0|g; s|@UPGRADECODE@|0F0E0D0C-0B0A-4908-8706-050403020100|g" \
      -e "s|@ICON@|$here/../../ime/res/viettelex.ico|g; s|@BIN_NATIVE@|$d|g; s|@BIN_X86@|$d|g" \
      -e "s|@GUID_APP@|0F0E0D0C-0B0A-4908-8706-050403020101|; s|@GUID_TIPNATIVE@|0F0E0D0C-0B0A-4908-8706-050403020102|" \
      -e "s|@GUID_TIPX86@|0F0E0D0C-0B0A-4908-8706-050403020103|; s|@GUID_SHORTCUT@|0F0E0D0C-0B0A-4908-8706-050403020104|" \
      -e "/@ARM64_/d" "$here/viettelex.wxs.in"
}
dll='[INSTALLFOLDER]VietTelexTIP.dll'

# ---- the 1.0.0 way
fill | sed '/@REG_/d' > "$d/old.wxs"
wixl --arch x64 -o "$d/old.msi" "$d/old.wxs" 2>/dev/null
"$REGTABLE" rows TipNative "$dll" "$dll" | python3 -c '
import subprocess, sys
for n, line in enumerate(sys.stdin.read().splitlines()):
    root, key, name, value, comp = line.split("\t")
    q = ("INSERT INTO `Registry` (`Registry`,`Root`,`Key`,`Name`,`Value`,`Component_`) "
         "VALUES (\x27vtx_%s_%02d\x27,2,\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27)" % (comp, n, key, name, value, comp))
    subprocess.run(["msibuild", sys.argv[1], "-q", q], check=True)
' "$d/old.msi"
if python3 "$here/check_msi.py" "$d/old.msi" 2>/dev/null; then
  echo "FAIL: check_msi.py accepted the 1.0.0-style MSI (rows inserted with msibuild -q)" >&2; exit 1
fi

# ---- the current way
"$REGTABLE" wxs TipNative "$dll" "$dll" > "$d/reg64.xml"
"$REGTABLE" wxs TipX86 '[INSTALLFOLDER86]VietTelexTIP.dll' '[INSTALLFOLDER86]VietTelexTIP.dll' > "$d/reg32.xml"
fill | sed -e "/@REG_TIPNATIVE@/r $d/reg64.xml" -e "/@REG_TIPNATIVE@/d" \
           -e "/@REG_TIPX86@/r $d/reg32.xml" -e "/@REG_TIPX86@/d" > "$d/new.wxs"
wixl --arch x64 -o "$d/new.msi" "$d/new.wxs" 2>/dev/null
python3 "$here/check_msi.py" "$d/new.msi" >/dev/null
msiinfo export "$d/new.msi" Registry > "$d/Registry.idt"
"$REGTABLE" check "$d/Registry.idt" TipNative "$dll" "$dll" >/dev/null
echo "check_msi regression ok (1.0.0-style MSI rejected, wixl-written MSI accepted)"
