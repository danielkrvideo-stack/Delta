#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release --arch x86_64

APP="Delta.app"
DELTA_VERSION="${DELTA_VERSION:-0.1.0}"
DELTA_BUILD_NUMBER="${DELTA_BUILD_NUMBER:-1}"
ICONSET=".build/Delta.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

swift Scripts/create-app-icon.swift "$ICONSET/icon_1024x1024.png"
sips -z 16 16 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cp ".build/x86_64-apple-macosx/release/Delta" "$APP/Contents/MacOS/Delta"
cp ".build/x86_64-apple-macosx/release/DeltaUpdateInstaller" "$APP/Contents/MacOS/DeltaUpdateInstaller"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Delta</string>
    <key>CFBundleIdentifier</key>
    <string>com.delta.browser</string>
    <key>CFBundleName</key>
    <string>Delta</string>
    <key>CFBundleShortVersionString</key>
    <string>${DELTA_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${DELTA_BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>HTML Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>html</string>
                <string>htm</string>
                <string>xhtml</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.html</string>
                <string>public.xhtml</string>
            </array>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
echo "Built $APP for Intel (x86_64). Launch with: open $APP"
