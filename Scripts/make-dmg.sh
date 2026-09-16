#!/bin/bash
# Dorso's drag-to-Applications layout, branded for Elbowroom.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?usage: make-dmg.sh /path/Elbowroom.app /path/output.dmg}"
DMG="${2:?output DMG path required}"
[ -d "$APP" ] || { echo "Missing app: $APP" >&2; exit 1; }
[ ! -e "$DMG" ] || { echo "Output already exists: $DMG" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "Install create-dmg: brew install create-dmg" >&2; exit 1; }
mkdir -p "$(dirname "$DMG")"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Elbowroom.app"
create-dmg --volname Elbowroom \
  --volicon "$APP/Contents/Resources/AppIcon.icns" \
  --background Assets/Installer/background.png \
  --window-pos 200 120 --window-size 654 444 --icon-size 128 --text-size 12 \
  --icon Elbowroom.app 197 195 --hide-extension Elbowroom.app \
  --app-drop-link 473 195 "$DMG" "$STAGING"
