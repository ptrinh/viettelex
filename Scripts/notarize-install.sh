#!/bin/zsh
# Build → Developer ID sign (hardened runtime) → notarize → staple → install.
# macOS 26 requires input methods to be NOTARIZED to register as input sources.
#
# One-time setup (run yourself, interactive, so the secret never passes through
# the agent). First create an app-specific password at appleid.apple.com
# (Sign-In and Security → App-Specific Passwords), then:
#   xcrun notarytool store-credentials VietTelexNotary \
#         --apple-id <your-apple-id-email> --team-id 84T567KMYD
#   (paste the app-specific password when prompted)
set -e
cd "$(dirname "$0")/.."

SIGN_ID="Developer ID Application: Phil Trinh (84T567KMYD)"
PROFILE="VietTelexNotary"
DEST="$HOME/Library/Input Methods/VietTelex.app"
SCRATCH="${TMPDIR:-/tmp}/viettelex-notarize"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Mỗi vòng xcodebuild build/test đăng ký thêm một VietTelex.app CÙNG bundle id với
# LaunchServices (xoá thư mục KHÔNG huỷ đăng ký — đo 13/09/2026: 4 bản ghi trong khi
# mdfind thấy 1). Khi IMK relaunch input method nó có thể chọn bản thừa: 23/09/2026
# một bản Debug cũ trong DerivedData được khởi động và chiếm luôn IMK connection của
# bản Release đã cài (gõ sai chữ, Enter xuống dòng thay vì gửi). Huỷ đăng ký MỌI bản
# ngoài $DEST, kể cả khi script fail giữa chừng (trap EXIT) — chính ca fail sau build
# để lại bản ghi mới. -u chỉ xoá bản ghi LaunchServices, không đụng file.
unregister_stray_copies() {
  "$LSREG" -dump 2>/dev/null | grep -E '^path:.*/VietTelex\.app \(0x' \
    | sed -E 's/^path: *//; s/ \(0x[0-9a-f]+\)$//' \
    | while IFS= read -r reg; do
        [ "$reg" = "$DEST" ] && continue
        "$LSREG" -u "$reg" >/dev/null 2>&1 && echo "  lsregister -u (bản thừa): $reg"
      done
}
trap unregister_stray_copies EXIT

echo "→ building"
xcodegen generate >/dev/null 2>&1 || true
# Explicit derivedDataPath: multiple stale DerivedData dirs made the old
# `ls | head -1` pick an OUTDATED build (shipped old icons/name once). Build
# and install from ONE deterministic location.
DERIVED="${TMPDIR:-/tmp}/viettelex-derived"
xcodebuild -project VietTelex.xcodeproj -scheme VietTelex \
           -configuration Release -destination 'platform=macOS' \
           -derivedDataPath "$DERIVED" \
           build | grep -E "BUILD" || true
APP="$DERIVED/Build/Products/Release/VietTelex.app"
[ -d "$APP" ] || { echo "build product not found: $APP"; exit 1; }

echo "→ cleaning stray legacy code seal + Developer ID sign + hardened runtime"
# xcodebuild leaves a legacy top-level Contents/CodeResources that no valid app
# (Apple's own IMEs, normal .apps) has. Strip it and the existing seal,
# then sign fresh so the bundle matches a clean modern signature.
rm -f "$APP/Contents/CodeResources"
codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --options runtime --timestamp \
         --entitlements App/Resources/VietTelex.entitlements \
         --sign "$SIGN_ID" "$APP"
if [ -f "$APP/Contents/CodeResources" ]; then
  echo "  WARNING: stray Contents/CodeResources reappeared after signing"; fi

echo "→ zipping + submitting to Apple notary (waits for result)"
mkdir -p "$SCRATCH"
ZIP="$SCRATCH/VietTelex.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "→ stapling the ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "→ installing to $DEST"
pkill -x VietTelex 2>/dev/null || true
rm -rf "$DEST"
/usr/bin/ditto "$APP" "$DEST"
"$LSREG" -f "$DEST"
unregister_stray_copies
spctl -a -t exec -vv "$DEST" 2>&1 | head -2
# DO NOT blanket-reset the Accessibility grant here (it used to, forcing a
# re-grant on EVERY install). The designated requirement is identity-based
# (identifier + team), so a same-identity re-sign normally keeps the grant
# valid. When macOS does wedge the grant anyway, the app now DETECTS it
# (trusted but tap-create refused) and walks the user through remove+re-add
# via the menu status line — see TerminalTapController.trustLooksStale.
pkill -x VietTelex 2>/dev/null || true

echo "Done. Log out / log in ONCE (first install only), then add it: Keyboard → Input Sources → + → Vietnamese → Tiếng Việt (VietTelex)."
echo "If Terminal/Chromium typing stops after this install, the IME menu will show"
echo "'Quyền trợ năng bị kẹt' with one-click repair instructions."
