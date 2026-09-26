#!/bin/sh
# The MSI registry check must accept exactly the DllRegisterServer data and reject any
# drift (missing, extra or changed row). Input format = `msiinfo export <msi> Registry`.
set -eu
T="$1"
d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
dll='[INSTALLFOLDER]VietTelexTIP.dll'; icon='[INSTALLFOLDER]VietTelexTIP.dll'
hdr() { printf 'Registry\tRoot\tKey\tName\tValue\tComponent_\r\ns72\ti2\tl255\tL255\tL0\ts72\r\nRegistry\tRegistry\r\n'; }
rows() { "$T" rows TipNative "$dll" "$icon" | awk -F'\t' '{printf "id%d\t%s\t%s\t%s\t%s\t%s\r\n", NR, $1, $2, $3, $4, $5}'; }
{ hdr; rows; printf 'other\t2\tSOFTWARE\\VietTelex\tAppPath\tx\tAppExe\r\n'; } > "$d/ok.idt"
"$T" check "$d/ok.idt" TipNative "$dll" "$icon" >/dev/null
{ hdr; rows | sed '1d'; } > "$d/missing.idt"
! "$T" check "$d/missing.idt" TipNative "$dll" "$icon" 2>/dev/null
{ hdr; rows; printf 'x\t2\tSOFTWARE\\Bogus\tv\t#1\tTipNative\r\n'; } > "$d/extra.idt"
! "$T" check "$d/extra.idt" TipNative "$dll" "$icon" 2>/dev/null
{ hdr; rows | sed 's/Apartment/Both/'; } > "$d/changed.idt"
! "$T" check "$d/changed.idt" TipNative "$dll" "$icon" 2>/dev/null
# wrong DLL path (e.g. the arm64 half registered instead of the forwarder)
! "$T" check "$d/ok.idt" TipNative '[INSTALLFOLDER]VietTelexTIP_arm64.dll' "$icon" 2>/dev/null
echo "regtable roundtrip ok"
