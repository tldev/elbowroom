#!/bin/bash
# Render the current app with isolated fixture data, then refresh README images.
set -euo pipefail
cd "$(dirname "$0")/.."
SNAPSHOTS=$(mktemp -d "${TMPDIR:-/tmp}/elbowroom-readme.XXXXXX")
trap 'rm -rf "$SNAPSHOTS"' EXIT
swift run ElbowroomSnapshots "$SNAPSHOTS"
mkdir -p docs/images
for appearance in light dark; do
  cp "$SNAPSHOTS/den-$appearance.png" "docs/images/overview-$appearance.png"
  cp "$SNAPSHOTS/ledger-$appearance.png" "docs/images/items-$appearance.png"
  cp "$SNAPSHOTS/cross-section-$appearance.png" "docs/images/map-$appearance.png"
  for view in reclaim-plan cleanup-docker; do
    cp "$SNAPSHOTS/$view-$appearance.png" "docs/images/$view-$appearance.png"
  done
done
