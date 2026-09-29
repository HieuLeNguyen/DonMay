#!/bin/bash
# Đóng gói DonMay.app từ bản build release của SwiftPM.
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal: chạy được trên cả Mac chip Apple lẫn Intel.
swift build -c release --arch arm64 --arch x86_64
PRODUCTS=.build/apple/Products/Release
APP=build/DonMay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/DonMay" "$APP/Contents/MacOS/DonMay"
cp -R "$PRODUCTS/DonMay_DonMay.bundle" "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dọn Máy</string>
  <key>CFBundleDisplayName</key><string>Dọn Máy</string>
  <key>CFBundleIdentifier</key><string>studio.thapp.donmay</string>
  <key>CFBundleExecutable</key><string>DonMay</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
# Ký ad-hoc với designated requirement chỉ theo bundle id: macOS nhớ quyền (Desktop, Documents,
# Downloads, Full Disk Access) qua các lần build lại. Ký mặc định theo cdhash thì mỗi lần build là
# một ứng dụng mới và macOS hỏi quyền lại từ đầu. Có chứng chỉ riêng thì đặt SIGN_IDENTITY.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - -r='designated => identifier "studio.thapp.donmay"' "$APP"
fi
echo "Đã tạo $APP"
