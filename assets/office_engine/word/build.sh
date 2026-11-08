#!/usr/bin/env bash
# macOS / Linux build entry point.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 build.py "$@"
