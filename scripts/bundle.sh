#!/bin/bash
# Сборка VTranslator.app (универсальный бинарник arm64 + x86_64), DMG и ZIP.
# Запускается на macOS (локально или в GitHub Actions).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_NAME="VTranslator"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Сборка Swift (release, universal)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Иконка"
rm -rf build/AppIcon.iconset
mkdir -p build
swift scripts/make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "==> Сборка .app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "==> Подпись (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"

echo "==> DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.txt "$STAGE/Как установить.txt"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME-$VERSION.dmg"
rm -rf "$STAGE"

echo "==> ZIP"
# Имя без версии — для постоянной ссылки releases/latest/download/VTranslator.zip (её использует install.sh).
(cd "$DIST" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")

ls -la "$DIST"
echo "Готово."
