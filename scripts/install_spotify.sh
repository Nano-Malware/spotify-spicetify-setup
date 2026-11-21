#!/usr/bin/env bash
# Compatibility wrapper for the pinned historical Spotify installer.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$SCRIPT_DIR/install_legacy_spotify.sh" "$@"
