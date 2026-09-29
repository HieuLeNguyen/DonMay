#!/bin/bash
# Đóng gói DonMay.app từ bản build release của SwiftPM.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/DonMay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DonMay "$APP/Contents/MacOS/DonMay"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dọn Máy</string>
  <key>CFBundleDisplayName</key><string>Dọn Máy</string>
  <key>CFBundleIdentifier</key><string>studio.thapp.donmay</string>
  <key>CFBundleExecutable</key><string>DonMay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Dọn Máy cần điều khiển Finder để dọn Thùng rác.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Đã tạo $APP"
