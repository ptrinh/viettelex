#!/bin/sh
# End-to-end MSI regression test for the installer bugs found on real Windows:
#   1.0.0 error 2211 (table rows out of key order), 1.0.3 error 2731 (CA before costing),
#   1.0.4 error 2753 (FileKey CA on repair).
#
#   check_msi_test.sh <vtx_regtable>
#
# Builds the real template (viettelex.wxs.in, dummy payload) and checks that it passes
# check_msi.py and the registry diff, then that the 1.0.3 (CA before costing) and 1.0.4
# (FileKey CA) mistakes, patched into a copy, are rejected.
# Needs wixl + msibuild (msitools); skipped (exit 0) without them.
set -eu
REGTABLE="$1"
here="$(cd "$(dirname "$0")" && pwd)"
command -v wixl >/dev/null 2>&1 && command -v msibuild >/dev/null 2>&1 || { echo "skip: msitools absent"; exit 0; }
d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
for f in VietTelex.exe VietTelexTIP_1_0_0.dll VietTelexSetupHelper.exe; do echo "$f" > "$d/$f"; done
fill() {
  sed -e "s|@VERSION@|1.0.0|g; s|@UPGRADECODE@|0F0E0D0C-0B0A-4908-8706-050403020100|g; s|@PRODUCTCODE@|*|g; s|@TIPDLL@|VietTelexTIP_1_0_0.dll|g" \
      -e "s|@GUID_TIPFILE@|0F0E0D0C-0B0A-4908-8706-050403020105|; s|@GUID_TIPFILE86@|0F0E0D0C-0B0A-4908-8706-050403020106|" \
      -e "s|@ICON@|$here/../../ime/res/viettelex.ico|g; s|@BIN_NATIVE@|$d|g; s|@BIN_X86@|$d|g" \
      -e "s|@GUID_APP@|0F0E0D0C-0B0A-4908-8706-050403020101|; s|@GUID_TIPNATIVE@|0F0E0D0C-0B0A-4908-8706-050403020102|" \
      -e "s|@GUID_TIPX86@|0F0E0D0C-0B0A-4908-8706-050403020103|; s|@GUID_SHORTCUT@|0F0E0D0C-0B0A-4908-8706-050403020104|" \
      -e "/@ARM64_/d" "$here/viettelex.wxs.in"
}
dll='[INSTALLFOLDER]VietTelexTIP_1_0_0.dll'

# (1.0.0 row-order and the other rules are unit-tested on plain data in
# check_msi_unit.py; this script checks the real template end to end.)

# ---- the current way
"$REGTABLE" wxs TipReg "$dll" "$dll" > "$d/reg64.xml"
"$REGTABLE" wxs TipReg86 '[INSTALLFOLDER86]VietTelexTIP_1_0_0.dll' '[INSTALLFOLDER86]VietTelexTIP_1_0_0.dll' > "$d/reg32.xml"
fill | sed -e "/@REG_TIPNATIVE@/r $d/reg64.xml" -e "/@REG_TIPNATIVE@/d" \
           -e "/@REG_TIPX86@/r $d/reg32.xml" -e "/@REG_TIPX86@/d" > "$d/new.wxs"
wixl --arch x64 -o "$d/new.msi" "$d/new.wxs" 2>/dev/null
# same post-step as release.sh: helper actions -> type 2 from the Binary table
msibuild "$d/new.msi" -q "UPDATE \`CustomAction\` SET \`Type\`=66, \`Source\`='SetupHelper' WHERE \`Action\`='QuitApp'"
msibuild "$d/new.msi" -q "UPDATE \`CustomAction\` SET \`Type\`=3138, \`Source\`='SetupHelper' WHERE \`Action\`='ReleaseTip'"
python3 "$here/check_msi.py" "$d/new.msi" >/dev/null
msiinfo export "$d/new.msi" Registry > "$d/Registry.idt"
"$REGTABLE" check "$d/Registry.idt" TipReg "$dll" "$dll" >/dev/null
# ---- 1.0.3 regression class: the installed exe's path used before CostFinalize ->
# Windows error 2731 on every uninstall. Must be rejected.
cp "$d/new.msi" "$d/seq.msi"
msibuild "$d/seq.msi" -q "UPDATE \`InstallExecuteSequence\` SET \`Sequence\`=1 WHERE \`Action\`='SetVtxExe'"
if python3 "$here/check_msi.py" "$d/seq.msi" 2>/dev/null; then
  echo "FAIL: check_msi.py accepted CleanupUser before CostFinalize (1.0.3, error 2731)" >&2; exit 1
fi
# ---- 1.0.4 regression: FileKey custom action (type 18, source = the VietTelex.exe File
# row) -> error 2753 on repair/maintenance. Must be rejected.
cp "$d/new.msi" "$d/filekey.msi"
msibuild "$d/filekey.msi" -q "UPDATE \`CustomAction\` SET \`Type\`=82, \`Source\`='VietTelexExe' WHERE \`Action\`='SetupUser'"
msiinfo export "$d/filekey.msi" CustomAction | grep -q "^SetupUser	82	VietTelexExe" || { echo "FAIL: test setup (UPDATE)" >&2; exit 1; }
if python3 "$here/check_msi.py" "$d/filekey.msi" 2>/dev/null; then
  echo "FAIL: check_msi.py accepted a FileKey custom action (1.0.4, error 2753)" >&2; exit 1
fi
# ---- 1.0.6 (error 2613): RemoveExistingProducts at 1510 with ReleaseTip between it
# and InstallInitialize is an ILLEGAL position (ICE63). Must be rejected.
cp "$d/new.msi" "$d/rep.msi"
msibuild "$d/rep.msi" -q "UPDATE \`InstallExecuteSequence\` SET \`Sequence\`=1510 WHERE \`Action\`='RemoveExistingProducts'"
msibuild "$d/rep.msi" -q "UPDATE \`InstallExecuteSequence\` SET \`Sequence\`=1505 WHERE \`Action\`='ReleaseTip'"
if python3 "$here/check_msi.py" "$d/rep.msi" 2>/dev/null; then
  echo "FAIL: check_msi.py accepted the 1.0.6 RemoveExistingProducts position (error 2613)" >&2; exit 1
fi
echo "check_msi regression ok (template accepted; 1.0.3 CA sequence, 1.0.4 FileKey CA, 1.0.6 REP position rejected)"
