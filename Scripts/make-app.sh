#!/bin/bash
# Build a direct-download app. Release packaging supplies an isolated output.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG=release
UNIVERSAL=false
DISTRIBUTION=false
APP="$ROOT/dist/Elbowroom.app"
while [ "$#" -gt 0 ]; do
  case "$1" in
    debug|release) CONFIG="$1" ;;
    --universal) UNIVERSAL=true ;;
    --distribution) DISTRIBUTION=true; UNIVERSAL=true ;;
    --output) shift; APP="${1:?--output needs a path}" ;;
    *) echo "usage: $0 [debug|release] [--universal] [--distribution] [--output PATH]" >&2; exit 2 ;;
  esac
  shift
done
[ "$DISTRIBUTION" = false ] || [ "$CONFIG" = release ] || { echo "Distribution requires release configuration" >&2; exit 2; }
# Refuse accidental output paths; only replace an explicitly named app bundle.
[[ "$APP" = /*/Elbowroom.app ]] || { echo "Output must be an absolute path ending in /Elbowroom.app" >&2; exit 2; }
IDENTITY="${DEVELOPER_ID:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ && !/REVOKED/ {print $2; exit}')
fi
if [ "$DISTRIBUTION" = true ]; then
  [ -n "$IDENTITY" ] || { echo "A Developer ID Application identity is required" >&2; exit 1; }
elif [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development/ && !/REVOKED/ {print $2; exit}')
fi
ARCHES=("$(uname -m)")
if [ "$UNIVERSAL" = true ]; then ARCHES=(arm64 x86_64); fi
LINK_FLAGS=(-Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
BIN_DIRS=()
for arch in "${ARCHES[@]}"; do
  swift build -c "$CONFIG" --arch "$arch" --product Elbowroom "${LINK_FLAGS[@]}"
  swift build -c "$CONFIG" --arch "$arch" --product ElbowroomAppMover
  BIN_DIRS+=("$(swift build -c "$CONFIG" --arch "$arch" --show-bin-path)")
done
mkdir -p "$(dirname "$APP")"
STAGING=$(mktemp -d "$(dirname "$APP")/.elbowroom-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/Elbowroom.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$BUNDLE/Contents/Frameworks"
for executable in Elbowroom ElbowroomAppMover; do
  if [ "$UNIVERSAL" = true ]; then
    lipo -create "${BIN_DIRS[0]}/$executable" "${BIN_DIRS[1]}/$executable" -output "$BUNDLE/Contents/MacOS/$executable"
  else
    cp "${BIN_DIRS[0]}/$executable" "$BUNDLE/Contents/MacOS/$executable"
  fi
done
ditto "${BIN_DIRS[0]}/Elbowroom_ElbowroomKit.bundle" "$BUNDLE/Contents/Resources/Elbowroom_ElbowroomKit.bundle"
cp Assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$BUNDLE/Contents/Frameworks/Sparkle.framework"
python3 - "$BUNDLE" "$DISTRIBUTION" <<'PY'
import json, plistlib, sys
from pathlib import Path
meta = json.loads(Path('release.json').read_text())
if sys.argv[2] == 'true' and not meta['sparkle_public_key']:
    raise SystemExit('Set up the Sparkle signing key before distribution.')
info = dict(CFBundleDevelopmentRegion='en', CFBundleLocalizations=['en', 'ja'],
    CFBundleExecutable='Elbowroom', CFBundleIconFile='AppIcon',
    CFBundleIdentifier=meta['bundle_id'], CFBundleInfoDictionaryVersion='6.0',
    CFBundleName='Elbowroom', CFBundleDisplayName='Elbowroom', CFBundlePackageType='APPL',
    CFBundleShortVersionString=meta['version'], CFBundleVersion=str(meta['build']),
    LSMinimumSystemVersion=meta['minimum_macos'], NSAccentColorName='AccentColor',
    NSHighResolutionCapable=True, NSHumanReadableCopyright='Room to build.',
    SUFeedURL=f"https://raw.githubusercontent.com/{meta['repository']}/main/appcast.xml",
    SUPublicEDKey=meta['sparkle_public_key'], SUEnableAutomaticChecks=True,
    SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
    ElbowroomDistributionBuild=sys.argv[2] == 'true')
with (Path(sys.argv[1])/'Contents/Info.plist').open('wb') as f: plistlib.dump(info, f)
PY
if [ -d Assets/Assets.xcassets ] && xcrun --find actool >/dev/null 2>&1; then
  xcrun actool Assets/Assets.xcassets --compile "$BUNDLE/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$STAGING/asset-info.plist" >/dev/null
fi
SIGN_ARGS=(--force --sign "${IDENTITY:--}")
if [ -n "$IDENTITY" ]; then SIGN_ARGS+=(--options runtime); fi
if [ "$DISTRIBUTION" = true ]; then SIGN_ARGS+=(--timestamp); fi
FW="$BUNDLE/Contents/Frameworks/Sparkle.framework"
# Sign inside-out; preserve Sparkle's downloader entitlements and symlinks.
for part in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$FW/Versions/B/$part"
done
codesign "${SIGN_ARGS[@]}" "$FW"
codesign "${SIGN_ARGS[@]}" "$BUNDLE/Contents/MacOS/ElbowroomAppMover"
codesign "${SIGN_ARGS[@]}" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
# All expensive work and validation finish before replacing the output bundle.
rm -rf "$APP"
mv "$BUNDLE" "$APP"
echo "Built $APP"
lipo -archs "$APP/Contents/MacOS/Elbowroom"
