#!/bin/bash
set -e

APP_NAME="Periphera"
DMG_NAME="${APP_NAME}.dmg"
STAGING_DIR="./build_dmg_staging"

echo "🔨 1/3 Compilazione di ${APP_NAME} in modalità Release..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    build -quiet

APP_PATH=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')/"${APP_NAME}.app"

echo "📦 2/3 Preparazione cartella con collegamento ad /Applications..."
rm -rf "${STAGING_DIR}" "${DMG_NAME}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "💿 3/3 Creazione di ${DMG_NAME}..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

rm -rf "${STAGING_DIR}"
echo "✅ DMG creato con successo: $(pwd)/${DMG_NAME}"
