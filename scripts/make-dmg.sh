#!/bin/bash
# Đóng DonMay.app thành build/DonMay.dmg: mở ra, kéo vào Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
STAGE=$(mktemp -d)
cp -R build/DonMay.app "$STAGE/Dọn Máy.app"
ln -s /Applications "$STAGE/Applications"
rm -f build/DonMay.dmg
hdiutil create -volname "Dọn Máy" -srcfolder "$STAGE" -format UDZO -ov build/DonMay.dmg >/dev/null
rm -rf "$STAGE"
if [ -n "${SIGN_IDENTITY:-}" ]; then codesign --force --sign "$SIGN_IDENTITY" build/DonMay.dmg; fi
echo "Đã tạo build/DonMay.dmg"
