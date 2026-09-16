#!/bin/bash
# Build a local installer preview without notarizing or publishing.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 Scripts/release.py --preview "$@"
