#!/bin/bash
set -euo pipefail

APP_NAME="Hex Picker"
BUNDLE_NAME="Hex Picker.app"
DMG_NAME="HexPicker.dmg"
BUILD_DIR="build"

echo "Building ${APP_NAME}..."

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/Resources"

swiftc -O -parse-as-library -o "${BUILD_DIR}/${BUNDLE_NAME}/Contents/MacOS/hex_picker" main.swift

cp Info.plist "${BUILD_DIR}/${BUNDLE_NAME}/Contents/"

echo "Creating DMG..."

rm -f "${BUILD_DIR}/${DMG_NAME}"

DMG_DIR="${BUILD_DIR}/dmg_staging"
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${BUILD_DIR}/${BUNDLE_NAME}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}"

rm -rf "${DMG_DIR}"

echo ""
echo "Done!"
echo "  App:  ${BUILD_DIR}/${BUNDLE_NAME}"
echo "  DMG:  ${BUILD_DIR}/${DMG_NAME}"
