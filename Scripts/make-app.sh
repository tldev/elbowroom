#!/bin/bash
# Build Elbowroom.app from the SwiftPM package.
# Usage: Scripts/make-app.sh [debug|release]
# Direct-download distribution only; no App Sandbox build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    *) echo "usage: $0 [debug|release] (direct distribution only)" >&2; exit 2 ;;
  esac
done

swift build -c "$CONFIG"

BIN=".build/$CONFIG"
APP="dist/Elbowroom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Elbowroom" "$APP/Contents/MacOS/Elbowroom"
cp "$BIN/ElbowroomAppMover" "$APP/Contents/MacOS/ElbowroomAppMover"
if [ -d "$BIN/Elbowroom_ElbowroomKit.bundle" ]; then
  cp -R "$BIN/Elbowroom_ElbowroomKit.bundle" "$APP/Contents/Resources/"
fi
if [ -f "Assets/AppIcon.icns" ]; then
  cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Accent color (NSAccentColorName): Table/List selection ignores SwiftUI
# .tint and reads the compiled catalog, so brand graphite instead of system
# blue needs an Assets.car in the bundle. Skipped when actool is absent;
# the app then falls back to the system accent.
if [ -d "Assets/Assets.xcassets" ] && xcrun --find actool >/dev/null 2>&1; then
  xcrun actool "Assets/Assets.xcassets" \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$(mktemp -t actool-plist)" >/dev/null
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
	<key>CFBundleExecutable</key><string>Elbowroom</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>dev.elbowroom.app</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Elbowroom</string>
	<key>CFBundleDisplayName</key><string>Elbowroom</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>2</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSAccentColorName</key><string>AccentColor</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSHumanReadableCopyright</key><string>Room to build.</string>
</dict>
</plist>
PLIST

# Stable identity even for the dev build: TCC grants (Full Disk Access,
# folder consents) key on the signing identity, so ad-hoc signing resets
# every grant on every rebuild. Fall back to ad-hoc when no cert exists.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep -v REVOKED | head -1 | awk '{print $2}' || true)
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | grep -v REVOKED | head -1 | awk '{print $2}' || true)
fi
if [ -n "$IDENTITY" ]; then
  echo "signing with stable identity $IDENTITY"
  codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/MacOS/ElbowroomAppMover"
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP/Contents/MacOS/ElbowroomAppMover"
  codesign --force --sign - "$APP" 2>/dev/null || true
fi

codesign -dv "$APP" 2>&1 | grep -E "Signature|Authority" | head -2 || true
echo "built $APP"
