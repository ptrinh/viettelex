#!/usr/bin/env bash
# Build, sign and package VietTelex for Windows — entirely from a Mac.
#
#   windows/scripts/release.sh --version 1.0.0 [--unsigned] [--skip-build]
#
#  1. Cross-compile engine + TIP + app for x86, x64, ARM64 with llvm-mingw in Docker
#     (mstorsjo/llvm-mingw; nothing is installed on the host), plus the ARM64X
#     pure-forwarder TIP (scripts/cross-build.sh).
#  2. Sign every .dll/.exe with jsign (Azure Artifact Signing, RFC 3161 timestamp).
#  3. Build one MSI per native architecture with wixl (msitools). COM/TSF registration
#     is RegistryValue rows generated from ime/core/registration.h — the data
#     DllRegisterServer uses — written by wixl; each built MSI is checked against it and
#     structurally (installer/msi/check_msi.py: row order, string refs, schemas). ARM64 MSI =
#     x64-shaped database with Template "Arm64;1033" (msibuild), as RelayKey does.
#  4. Sign the MSIs, verify every signature with osslsigncode against the Microsoft
#     root in installer/, write SHA256SUMS.
#  5. Stop. Nothing is uploaded or published.
#
# Host tools: docker (OrbStack), cmake + clang++ (host regtable tool), wixl/msibuild/
# msiinfo (msitools), jsign, osslsigncode, az (or CI client credentials).
#
# Signing target: VTX_SIGN_ENDPOINT, VTX_SIGN_ACCOUNT, VTX_SIGN_PROFILE — from the
# environment, else from the gitignored windows/installer/signing.local.env. Token:
# AZURE_TENANT_ID/AZURE_CLIENT_ID/AZURE_CLIENT_SECRET (CI) or `az login` (local).
# No secrets are ever written to disk by this script.
set -euo pipefail

WIN="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$WIN/.." && pwd)"
DIST="$WIN/dist"
IMAGE="mstorsjo/llvm-mingw:latest"
ROOTPEM="$WIN/installer/microsoft-identity-verification-root-2020.pem"

VERSION="" UNSIGNED=0 SKIP_BUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --unsigned) UNSIGNED=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    *) echo "usage: $0 --version X.Y.Z [--unsigned] [--skip-build]" >&2; exit 2 ;;
  esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "--version X.Y.Z is required" >&2; exit 2; }
V="_${VERSION//./_}"   # version-named TIP DLLs: VietTelexTIP_1_0_6.dll (cross-build.sh)

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 1; }; }
for t in docker cmake wixl msibuild msiinfo shasum; do need "$t"; done
if [ "$UNSIGNED" = 0 ]; then for t in jsign osslsigncode; do need "$t"; done; fi

echo "== VietTelex for Windows $VERSION"

# ------------------------------------------------------------------ 1. build
if [ "$SKIP_BUILD" = 0 ]; then
  rm -rf "$DIST"
  mkdir -p "$DIST"
  echo "-- cross-compiling in $IMAGE"
  docker run --rm -v "$ROOT:/src:ro" -v "$DIST:/out" "$IMAGE" sh /src/windows/scripts/cross-build.sh "$VERSION"
fi
for f in x86/VietTelexTIP$V.dll x64/VietTelexTIP$V.dll x64/VietTelex.exe arm64/VietTelex.exe \
         x64/VietTelexSetupHelper.exe arm64/VietTelexSetupHelper.exe \
         arm64/VietTelexTIP$V.dll arm64/VietTelexTIP_arm64$V.dll arm64/VietTelexTIP_x64$V.dll; do
  [ -f "$DIST/bin/$f" ] || { echo "missing build output bin/$f" >&2; exit 1; }
done

# Host-side generator/checker for the MSI registry rows (same core as the DLL).
HOSTB="$DIST/host"
cmake -S "$WIN" -B "$HOSTB" -DVTX_BUILD_TESTS=OFF -DVTX_IME_TESTS=OFF >/dev/null
cmake --build "$HOSTB" --target vtx_regtable >/dev/null
REGTABLE="$HOSTB/ime/vtx_regtable"

# ------------------------------------------------------------------ signing helpers
if [ "$UNSIGNED" = 0 ]; then
  if [ -f "$WIN/installer/signing.local.env" ]; then
    # shellcheck disable=SC1091
    set -a; . "$WIN/installer/signing.local.env"; set +a
  fi
  for v in VTX_SIGN_ENDPOINT VTX_SIGN_ACCOUNT VTX_SIGN_PROFILE; do
    [ -n "${!v:-}" ] || { echo "signing target not configured: $v (or pass --unsigned)" >&2; exit 1; }
  done
fi

signing_token() {
  if [ -n "${AZURE_TENANT_ID:-}" ] && [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_CLIENT_SECRET:-}" ]; then
    curl -fsS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
      -d "client_id=${AZURE_CLIENT_ID}" -d "client_secret=${AZURE_CLIENT_SECRET}" \
      -d "scope=https://codesigning.azure.net/.default" -d "grant_type=client_credentials" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
    return
  fi
  command -v az >/dev/null 2>&1 || return 1
  az account get-access-token --scope https://codesigning.azure.net/.default --query accessToken -o tsv 2>/dev/null
}

TOKEN=""
# Program name baked into the Authenticode signature (SpcSpOpusInfo). UAC shows THIS —
# without it Windows shows the temp copy msiexec makes (e.g. "130518b5.msi").
sign_name() { case "$1" in *.msi) echo "VietTelex Setup" ;; *) echo "VietTelex" ;; esac; }
sign() {  # sign <file>...
  [ "$UNSIGNED" = 1 ] && return 0
  if [ -z "$TOKEN" ]; then
    TOKEN="$(signing_token)" || TOKEN=""
    [ -n "$TOKEN" ] || { echo "no Azure signing token: run 'az login' or set AZURE_* for CI" >&2; exit 1; }
  fi
  local f
  for f in "$@"; do
    jsign --storetype TRUSTEDSIGNING --keystore "$VTX_SIGN_ENDPOINT" --storepass "$TOKEN" \
      --alias "$VTX_SIGN_ACCOUNT/$VTX_SIGN_PROFILE" \
      --name "$(sign_name "$f")" --url https://viettelex.com \
      --tsaurl http://timestamp.acs.microsoft.com/ --tsmode RFC3161 "$f" >/dev/null \
      || { echo "signing failed: $f" >&2; exit 1; }
  done
}

verify() {  # verify <file>... — read the signature back off the bytes, with the MS root
  [ "$UNSIGNED" = 1 ] && return 0
  local f out
  for f in "$@"; do
    out="$(osslsigncode verify -CAfile "$ROOTPEM" -TSA-CAfile "$ROOTPEM" "$f" 2>&1)" \
      || { echo "$out" >&2; echo "signature does not verify: $f" >&2; exit 1; }
    grep -q "Signature verification: ok" <<<"$out" || { echo "$out" >&2; exit 1; }
    grep -q "Timestamp Server Signature verification: ok" <<<"$out" \
      || { echo "$out" >&2; echo "no valid timestamp: $f" >&2; exit 1; }
  done
}

# ------------------------------------------------------------------ 2. sign binaries
rm -f "$DIST/bin/x86/VietTelex.exe"  # the app ships x64/arm64 only; x86 is just the 32-bit TIP
BINS=()
while IFS= read -r f; do BINS+=("$f"); done < <(find "$DIST/bin" -type f \( -name '*.dll' -o -name '*.exe' \) | sort)
echo "-- signing ${#BINS[@]} binaries"
sign "${BINS[@]}"
verify "${BINS[@]}"

# ------------------------------------------------------------------ 3. MSIs
guid() { printf '%s' "$1" | shasum -a 1 | awk '{u=toupper($1); printf "%s-%s-%s-%s-%s\n", substr(u,1,8), substr(u,9,4), substr(u,13,4), substr(u,17,4), substr(u,21,12)}'; }
OUT="$DIST/release"
mkdir -p "$OUT"
table() { msiinfo export "$1" "$2" | tr -d '\r'; }

build_msi() {  # build_msi <x64|arm64>
  local arch="$1" productcode="*" suffix="" upgrade icon_native
  # UpgradeCodes are the product identity across versions: NEVER change them. One per
  # architecture so the x64 and arm64 packages never treat each other as upgrades.
  case "$arch" in
    x64)   upgrade=C7AF803E-D7DC-4371-9318-04EA3B66BF59; icon_native="[INSTALLFOLDER]VietTelexTIP$V.dll" ;;
    # DllRegisterServer runs in the arm64 half (it holds the icon); InprocServer32 is
    # the forwarder (ime/core/com_path.h). The MSI mirrors exactly that.
    arm64) upgrade=5E0A7C41-9B3D-4F62-A8E1-7D2C4B9F3A06; icon_native="[INSTALLFOLDER]VietTelexTIP_arm64$V.dll" ;;
  esac
  local msi="$OUT/VietTelex-$VERSION-$arch$suffix.msi" work
  work="$(mktemp -d)"
  local arm64comp="" arm64refs=""
  if [ "$arch" = arm64 ]; then
    arm64comp="<Component Id=\"TipArm64Half\" Guid=\"$(guid "vtx-msi-tiparm64-$arch-$VERSION")\" Win64=\"yes\"><File Id=\"TipArm64Dll\" Name=\"VietTelexTIP_arm64$V.dll\" Source=\"$DIST/bin/arm64/VietTelexTIP_arm64$V.dll\" KeyPath=\"yes\" DefaultVersion=\"$VERSION.0\" DefaultLanguage=\"1033\" /></Component><Component Id=\"TipX64Half\" Guid=\"$(guid "vtx-msi-tipx64-$arch-$VERSION")\" Win64=\"yes\"><File Id=\"TipX64Dll\" Name=\"VietTelexTIP_x64$V.dll\" Source=\"$DIST/bin/arm64/VietTelexTIP_x64$V.dll\" KeyPath=\"yes\" DefaultVersion=\"$VERSION.0\" DefaultLanguage=\"1033\" /></Component>"
    arm64refs='<ComponentRef Id="TipArm64Half" /><ComponentRef Id="TipX64Half" />'
  fi
  sed -e "s|@VERSION@|$VERSION|g" -e "s|@UPGRADECODE@|$upgrade|g" -e "s|@PRODUCTCODE@|$productcode|g" -e "s|@TIPDLL@|VietTelexTIP$V.dll|g" -e "s|@FILEVERSION@|$VERSION.0|g" \
      -e "s|@ICON@|$WIN/ime/res/viettelex.ico|g" \
      -e "s|@BIN_NATIVE@|$DIST/bin/$arch|g" -e "s|@BIN_X86@|$DIST/bin/x86|g" \
      -e "s|@GUID_APP@|$(guid "vtx-msi-app-$arch")|g" -e "s|@GUID_TIPNATIVE@|$(guid "vtx-msi-tipnative-$arch")|g" \
      -e "s|@GUID_TIPX86@|$(guid "vtx-msi-tipx86-$arch")|g" \
      -e "s|@GUID_TIPFILE@|$(guid "vtx-msi-tipfile-$arch-$VERSION")|g" -e "s|@GUID_TIPFILE86@|$(guid "vtx-msi-tipfile86-$arch-$VERSION")|g" -e "s|@GUID_SHORTCUT@|$(guid "vtx-msi-shortcut-$arch")|g" \
      -e "s|<!-- @ARM64_COMPONENTS@ -->|$arm64comp|" -e "s|<!-- @ARM64_REFS@ -->|$arm64refs|" \
      "$WIN/installer/msi/viettelex.wxs.in" > "$work/product.in"
  # COM + TSF registration rows, written by wixl itself (see regtable.cpp for why
  # never msibuild -q): 64-bit view (TipNative), 32-bit view (TipX86).
  "$REGTABLE" wxs TipReg "[INSTALLFOLDER]VietTelexTIP$V.dll" "$icon_native" > "$work/reg64.xml"
  "$REGTABLE" wxs TipReg86 "[INSTALLFOLDER86]VietTelexTIP$V.dll" "[INSTALLFOLDER86]VietTelexTIP$V.dll" > "$work/reg32.xml"
  sed -e "/@REG_TIPNATIVE@/r $work/reg64.xml" -e "/@REG_TIPNATIVE@/d" \
      -e "/@REG_TIPX86@/r $work/reg32.xml" -e "/@REG_TIPX86@/d" "$work/product.in" > "$work/product.wxs"
  if grep -q '@[A-Z0-9_]*@' "$work/product.wxs"; then
    echo "unfilled placeholder in wxs:" >&2; grep -o '@[A-Z0-9_]*@' "$work/product.wxs" >&2; exit 1
  fi
  rm -f "$msi"
  wixl --arch x64 -o "$msi" "$work/product.wxs" 2> >(grep -v 'GLib-GObject-CRITICAL' >&2)
  [ -f "$msi" ] || { echo "wixl produced no MSI for $arch" >&2; exit 1; }
  # QuitApp / ReleaseTip -> type 2 (exe from the Binary table "SetupHelper"); wixl cannot
  # author BinaryKey+ExeCommand. Non-key columns only, so row order is untouched.
  #   66   = 2 + 64 (ignore exit code), immediate, impersonated
  #   3138 = 2 + 64 + 1024 (deferred) + 2048 (no impersonation: SYSTEM)
  msibuild "$msi" -q "UPDATE \`CustomAction\` SET \`Type\`=66, \`Source\`='SetupHelper' WHERE \`Action\`='QuitApp'"
  msibuild "$msi" -q "UPDATE \`CustomAction\` SET \`Type\`=3138, \`Source\`='SetupHelper' WHERE \`Action\`='ReleaseTip'"
  # wixl writes DefaultVersion but not DefaultLanguage: set File.Language (non-key column).
  msibuild "$msi" -q "UPDATE \`File\` SET \`Language\`='1033' WHERE \`Version\`='$VERSION.0'"

  local template=x64
  if [ "$arch" = arm64 ]; then
    # wixl only knows x86/x64/ia64: an Arm64 MSI is an x64-shaped database whose
    # summary Template says Arm64.
    template=Arm64
    local rev
    rev="$(msiinfo suminfo "$msi" | tr -d '\r' | awk -F': ' '/^Revision number/{print $2}')"
    msibuild "$msi" -s "Installation Database" "VietTelex" "Arm64;1033" "$rev"
  fi

  # ---- read it back the way Windows will
  local fail=0
  # Byte-level structure: every table's rows in primary-key order, string refs valid,
  # standard schemas (the 1.0.0 error-2211 class). Run BEFORE any other check.
  python3 "$WIN/installer/msi/check_msi.py" --version "$VERSION.0" "$msi" || fail=1
  msiinfo export "$msi" Registry > "$work/Registry.idt"
  "$REGTABLE" check "$work/Registry.idt" TipReg "[INSTALLFOLDER]VietTelexTIP$V.dll" "$icon_native" >/dev/null || fail=1
  "$REGTABLE" check "$work/Registry.idt" TipReg86 "[INSTALLFOLDER86]VietTelexTIP$V.dll" "[INSTALLFOLDER86]VietTelexTIP$V.dll" >/dev/null || fail=1
  # 64-bit components must have msidbComponentAttributes64bit (256), TipX86 must not.
  local c
  for c in AppExe TipNative TipReg; do
    table "$msi" Component | awk -F'\t' -v c="$c" '$1==c && int($4/256)%2==1{ok=1} END{exit !ok}' \
      || { echo "$c is not a 64-bit component" >&2; fail=1; }
  done
  table "$msi" Component | awk -F'\t' '$1=="TipX86" && int($4/256)%2==0{ok=1} END{exit !ok}' \
    || { echo "TipX86 is not a 32-bit component" >&2; fail=1; }
  table "$msi" Component | awk -F'\t' '$1=="TipReg86" && int($4/256)%2==0{ok=1} END{exit !ok}' \
    || { echo "TipReg86 is not a 32-bit component" >&2; fail=1; }
  table "$msi" Shortcut | grep -q '\[INSTALLFOLDER\]VietTelex.exe' || { echo "no Start menu shortcut" >&2; fail=1; }
  table "$msi" Upgrade | grep -q "^{$upgrade}	" || { echo "no Upgrade row" >&2; fail=1; }
  table "$msi" Property | grep -q "^ProductVersion	$VERSION\$" || { echo "ProductVersion != $VERSION" >&2; fail=1; }
  table "$msi" Property | grep -q "^ALLUSERS	1\$" || { echo "not per-machine" >&2; fail=1; }
  local a
  for a in InstallFiles WriteRegistryValues RemoveRegistryValues CreateShortcuts RegisterProduct PublishProduct InstallFinalize; do
    table "$msi" InstallExecuteSequence | grep -q "^$a	" || { echo "sequence missing $a" >&2; fail=1; }
  done
  local files="VietTelex.exe VietTelexTIP$V.dll"
  [ "$arch" = arm64 ] && files="$files VietTelexTIP_arm64$V.dll VietTelexTIP_x64$V.dll"
  for f in $files; do
    table "$msi" File | grep -q "	$f	" || { echo "MSI lacks $f" >&2; fail=1; }
  done
  msiinfo suminfo "$msi" | tr -d '\r' | grep -q "Template: $template;" || { echo "template is not $template" >&2; fail=1; }
  rm -rf "$work"
  [ "$fail" = 0 ] || { echo "MSI checks failed for $arch" >&2; exit 1; }
  echo "  msi $(basename "$msi"): $template, registry rows match DllRegisterServer data"
}

echo "-- building MSIs"
build_msi x64
build_msi arm64

MSIS=("$OUT/VietTelex-$VERSION-x64.msi" "$OUT/VietTelex-$VERSION-arm64.msi")
echo "-- signing MSIs"
sign "${MSIS[@]}"
verify "${MSIS[@]}" "${BINS[@]}"
# Loose signed binaries next to the MSIs (for inspection / winget portable use later).
for arch in x86 x64 arm64; do
  mkdir -p "$OUT/bin-$arch"
  cp "$DIST/bin/$arch/"*.dll "$DIST/bin/$arch/"*.exe "$OUT/bin-$arch/" 2>/dev/null || true
done
( cd "$OUT" && find . -type f \( -name '*.msi' -o -name '*.dll' -o -name '*.exe' \) | sed 's|^\./||' | sort \
    | xargs shasum -a 256 > SHA256SUMS )
if [ "$UNSIGNED" = 1 ]; then
  echo "== done (UNSIGNED): $OUT"
else
  echo "== done: $OUT — ${#BINS[@]} binaries + ${#MSIS[@]} MSIs signed, timestamped and verified"
fi
echo "   Nothing was uploaded. Publishing is a separate, deliberate step."
