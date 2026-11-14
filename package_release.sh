#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"
APP_NAME="MacAppCleaner"
VERSION="1.1.1"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
RELEASES_DIR="${PROJECT_DIR}/releases"
DOCS_DIR="${PROJECT_DIR}/docs"
DOCS_DL_DIR="${DOCS_DIR}/downloads"

echo "=== 1. Build release binary và App Bundle ==="
./build_app.sh

mkdir -p "${RELEASES_DIR}" "${DOCS_DL_DIR}"

echo "=== 2. Đóng gói file .ZIP ==="
ZIP_NAME="${APP_NAME}-v${VERSION}.zip"
ZIP_PATH="${RELEASES_DIR}/${ZIP_NAME}"
rm -f "${ZIP_PATH}"
/usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
echo "Đã tạo: ${ZIP_PATH}"

echo "=== 3. Đóng gói file .DMG (kèm shortcut kéo thả Applications) ==="
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
DMG_PATH="${RELEASES_DIR}/${DMG_NAME}"
STAGING_DIR="${PROJECT_DIR}/.build/dmg_staging"

rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

# Copy app và tạo symlink Applications
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# Tạo DMG nén UDZO
hdiutil create -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}"

rm -rf "${STAGING_DIR}"
echo "Đã tạo: ${DMG_PATH}"

echo "=== 4. Tạo mã băm SHA-256 ==="
CHECKSUM_FILE="${RELEASES_DIR}/checksums.sha256"
cd "${RELEASES_DIR}"
shasum -a 256 "${DMG_NAME}" "${ZIP_NAME}" > "${CHECKSUM_FILE}"
cat "${CHECKSUM_FILE}"
cd "${PROJECT_DIR}"

echo "=== 5. Đồng bộ vào docs/downloads cho GitHub Pages ==="
cp "${ZIP_PATH}" "${DOCS_DL_DIR}/"
cp "${DMG_PATH}" "${DOCS_DL_DIR}/"
cp "${CHECKSUM_FILE}" "${DOCS_DL_DIR}/"

echo "=== HOÀN TẤT ĐÓNG GÓI! ==="
ls -lh "${RELEASES_DIR}"
