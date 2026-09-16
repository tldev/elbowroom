#!/bin/bash
# Local, signed and notarized artifacts by default. --publish ships to GitHub.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 Scripts/release.py "$@"
