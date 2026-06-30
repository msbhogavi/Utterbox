#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.codex-build/release"
APP_NAME="Utterbox"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$ROOT_DIR/$APP_NAME.dmg"
ICON_SOURCE="$ROOT_DIR/NotchPrompter/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png"
STATUS_ICON_SOURCE="$ROOT_DIR/NotchPrompter/Assets.xcassets/StatusIcon.imageset/StatusIcon.pdf"
ENTITLEMENTS="$ROOT_DIR/NotchPrompter/NotchPrompter.entitlements"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("$file")
done < <(find "$ROOT_DIR/NotchPrompter" -maxdepth 1 -name '*.swift' ! -name 'Item.swift' | sort)

swiftc \
  -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 \
  -O \
  -parse-as-library \
  "${SWIFT_FILES[@]}" \
  -o "$MACOS_DIR/$APP_NAME" \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -framework Speech

cp "$STATUS_ICON_SOURCE" "$RESOURCES_DIR/StatusIcon.pdf"
cp "$ICON_SOURCE" "$RESOURCES_DIR/AppLogo.png"

ICONSET_DIR="$BUILD_DIR/$APP_NAME.iconset"
mkdir -p "$ICONSET_DIR"
sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$APP_NAME.icns"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME.icns</string>
  <key>CFBundleIdentifier</key>
  <string>arjuino.Utterbox</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Utterbox listens to your voice to follow the script while you present.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Utterbox uses speech recognition to advance the prompter as you read.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" --options runtime "$APP_DIR"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Built $APP_DIR"
echo "Built $DMG_PATH"
