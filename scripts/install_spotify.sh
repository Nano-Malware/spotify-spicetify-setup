#!/usr/bin/env bash
# Compatibility wrapper: prefer the tested build, otherwise install Flathub stable.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$SCRIPT_DIR/recover_known_good.sh" "${@}"
