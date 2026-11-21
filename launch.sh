#!/usr/bin/env bash
# Single entry point: install/check Spotify and launch it without patching files.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$PROJECT_DIR/scripts/common.sh"

if [[ ! -f "$PROJECT_DIR/.setup-dir" && -z "${SPOTIFY_SETUP_DIR:-}" ]]; then
    "$PROJECT_DIR/scripts/detect.sh"
fi
init_paths

require_command flatpak
require_command flock
require_command curl
require_command python3
require_command tar
require_command unzip
require_command awk

# Prevent two launcher processes from changing the same user installation.
exec 9>"$SETUP_DIR/.launch.lock"
flock -n 9 || die "Another Spotify setup/launch process is already running."

if ! spotify_is_installed; then
    info "Spotify is not installed in this project's user Flatpak directory."
    "$PROJECT_DIR/scripts/recover_known_good.sh" --yes
else
    SPOTIFY_VERSION="$(spotify_installed_version || true)"
    info "Found user-installed Spotify${SPOTIFY_VERSION:+ version $SPOTIFY_VERSION}."
fi

ensure_user_spotify_installed

# Keep the official CLI available, but do not modify Spotify's application files.
if [[ ! -x "$SPICETIFY_BIN" ]]; then
    "$PROJECT_DIR/scripts/install_spicetify.sh"
fi

ok "Spotify is ready. Launching the unmodified Spotify client."
exec flatpak run --user "$APP_ID" "$@"
