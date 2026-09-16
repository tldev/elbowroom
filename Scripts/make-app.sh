#!/bin/bash
# Build Elbowroom.app from the SwiftPM package.
# Usage: Scripts/make-app.sh [debug|release] [--sandbox]
#   --sandbox  sign with entitlements (App Sandbox + user-selected files +
#              security-scoped bookmarks) using the best identity available.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
SANDBOX=0
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --sandbox) SANDBOX=1 ;;
  esac
done

swift build -c "$CONFIG"

BIN=".build/$CONFIG"
APP="dist/Elbowroom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Elbowroom" "$APP/Contents/MacOS/Elbowroom"
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
	<key>CFBundleIdentifier</key><string>io.elbowroom.app</string>
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

if [ "$SANDBOX" = "1" ]; then
  # Sign by certificate hash: names can be ambiguous when a keychain holds
  # several certs with the same subject. Prefer Developer ID, else Apple
  # Development.
  IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep -v REVOKED | head -1 | awk '{print $2}')
  if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | grep -v REVOKED | head -1 | awk '{print $2}')
  fi
  if [ -z "$IDENTITY" ]; then
    echo "no signing identity found; cannot sandbox" >&2
    exit 1
  fi
  echo "signing sandboxed with identity $IDENTITY"
  codesign --force --options runtime \
    --entitlements Resources/Elbowroom.entitlements \
    --sign "$IDENTITY" "$APP"
else
  # Stable identity even for the dev build: TCC grants (Full Disk Access,
  # folder consents) key on the signing identity, so ad-hoc signing resets
  # every grant on every rebuild. Fall back to ad-hoc when no cert exists.
  IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep -v REVOKED | head -1 | awk '{print $2}' || true)
  if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | grep -v REVOKED | head -1 | awk '{print $2}' || true)
  fi
  if [ -n "$IDENTITY" ]; then
    echo "signing with stable identity $IDENTITY"
    codesign --force --sign "$IDENTITY" "$APP"
  else
    codesign --force --sign - "$APP" 2>/dev/null || true
  fi
fi

codesign -dv "$APP" 2>&1 | grep -E "Signature|Authority" | head -2 || true
echo "built $APP"
