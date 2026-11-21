#!/usr/bin/env bash
# Compatibility wrapper: only install the project's pinned, tested Spotify build.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$SCRIPT_DIR/recover_known_good.sh" "${@}"
