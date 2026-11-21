#!/usr/bin/env bash
# Backwards-compatible alias. launch.sh is the only setup/launch entry point.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$PROJECT_DIR/launch.sh" "$@"
