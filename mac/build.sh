#!/bin/bash
# Builds dist/Utter.app, signed and ready to run. `./build.sh install` also copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
FEED="${FEED:-https://github.com/thebigjah/utter/releases/latest/download/appcast.xml}"
PUBLIC_KEY="wDvhbubIXLmVHD6uwliTeBIiXcVGuOJutJXPHZFL9aM="
IDENTITY="${IDENTITY:-Apple Development: Elijah Purcell (V227VAM38S)}"

swift build -c release
BIN=.build/release
APP=dist/Utter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Utter" "$APP/Contents/MacOS/Utter"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

ICONSET="$(mktemp -d)/Utter.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  "$BIN/Utter" --render-icon "$ICONSET/icon_${s}x${s}.png" "$s"
  "$BIN/Utter" --render-icon "$ICONSET/icon_${s}x${s}@2x.png" "$((s * 2))"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Utter.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.purcellventures.utter</string>
  <key>CFBundleName</key><string>Utter</string>
  <key>CFBundleDisplayName</key><string>Utter</string>
  <key>CFBundleExecutable</key><string>Utter</string>
  <key>CFBundleIconFile</key><string>Utter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Purcell Ventures LLC</string>
  <key>NSMicrophoneUsageDescription</key><string>Utter listens only while you hold the dictation key, and transcribes on this Mac.</string>
  <key>SUFeedURL</key><string>${FEED}</string>
  <key>SUPublicEDKey</key><string>${PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# Sign inside-out, the order Sparkle's docs require.
F="$APP/Contents/Frameworks/Sparkle.framework"
codesign -f -s "$IDENTITY" -o runtime "$F/Versions/B/XPCServices/Installer.xpc"
codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$F/Versions/B/XPCServices/Downloader.xpc"
codesign -f -s "$IDENTITY" -o runtime "$F/Versions/B/Autoupdate"
codesign -f -s "$IDENTITY" -o runtime "$F/Versions/B/Updater.app"
codesign -f -s "$IDENTITY" -o runtime "$F"
codesign -f -s "$IDENTITY" -o runtime --entitlements Utter.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($VERSION build $BUILD)"

if [[ "${1:-}" == "install" ]]; then
  osascript -e 'tell application "Utter" to quit' 2>/dev/null || true
  rm -rf /Applications/Utter.app
  ditto "$APP" /Applications/Utter.app
  echo "Installed to /Applications/Utter.app"
fi
