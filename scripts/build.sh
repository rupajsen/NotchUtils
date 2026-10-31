#!/bin/zsh
# SPDX-License-Identifier: MIT
# Builds NotchUtils.app into ./dist. Pass --install to also copy it to /Applications.
# Signs ad hoc unless SIGN_IDENTITY names a Developer ID certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)

swift build -c release

APP=dist/NotchUtils.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchUtils "$APP/Contents/MacOS/NotchUtils"
cp .build/release/NotchUtilsFanHelper "$APP/Contents/MacOS/NotchUtilsFanHelper"
cp scripts/helper/* "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NotchUtils</string>
    <key>CFBundleDisplayName</key><string>NotchUtils</string>
    <key>CFBundleIdentifier</key><string>io.github.rupajsen.notchutils</string>
    <key>CFBundleExecutable</key><string>NotchUtils</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Rupaj Sen. MIT License.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchUtils reads and controls what's playing in Spotify and Music.</string>
</dict>
</plist>
PLIST

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP/Contents/MacOS/NotchUtilsFanHelper"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/NotchUtils.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/NotchUtils.app"
fi
