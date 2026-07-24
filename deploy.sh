#!/bin/bash
# Build Release + cài không dây lên iPhone 13 mini (Phil Tr).
# Dùng: ./deploy.sh
# Yêu cầu: iPhone mở khoá, chung WiFi với Mac.
set -euo pipefail

DEVICE_ID="2549E6A1-1FD4-55A3-8C8A-559743D3277E"
DERIVED="build/Release"
APP="$DERIVED/Build/Products/Release-iphoneos/VietTelexApp.app"

echo "▶︎ Build Release…"
xcodebuild -project VietTelex-iOS.xcodeproj \
  -scheme VietTelexApp \
  -configuration Release \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  build

echo "▶︎ Cài lên iPhone (WiFi)…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "✓ Xong — mở app VietTelex từ Home screen để test hiệu năng thật."
