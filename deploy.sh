#!/bin/bash
# Build Release + cài không dây lên iPhone 13 mini (Phil Tr).
# Dùng: ./deploy.sh
# Yêu cầu: iPhone mở khoá, chung WiFi với Mac.
set -euo pipefail

# UDID (xcodebuild + devicectl đều nhận). CoreDevice id cũ 2549E6A1… làm xcodebuild
# không tìm được destination (25/09/2026).
DEVICE_ID="00008110-00027C2222D9801E"
DERIVED="build/Release"
APP="$DERIVED/Build/Products/Release-iphoneos/VietTelexApp.app"

echo "▶︎ Build Release…"
xcodebuild -project VietTelex-iOS.xcodeproj \
  -scheme VietTelexApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  -derivedDataPath "$DERIVED" \
  build

echo "▶︎ Cài lên iPhone (WiFi)…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "✓ Xong — mở app VietTelex từ Home screen để test hiệu năng thật."
