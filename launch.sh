#!/usr/bin/env bash
# Single entry point: install the compatible Spotify build, then launch it.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$PROJECT_DIR/scripts/common.sh"

if [[ ! -f "$PROJECT_DIR/.setup-dir" ]]; then
    bash "$PROJECT_DIR/scripts/detect.sh"
fi
init_paths

require_command flatpak
require_command flock
require_command curl
require_command sha256sum
require_command awk
require_command grep

# Prevent two setup/launch processes from modifying the same user installation.
exec 9>"$SETUP_DIR/.launch.lock"
flock -n 9 || die "Another Spotify setup/launch process is already running."

if spotify_is_installed; then
    info "Current Goinfre Spotify: $(spotify_installed_version || printf unknown)"
else
    info "Spotify is not installed in the project-owned user Flatpak directory."
fi

# This is idempotent: it installs the pinned historical build only when needed,
# ensures its 24.08 runtime/Mesa extension, verifies it, and masks app updates.
bash "$PROJECT_DIR/scripts/install_legacy_spotify.sh"
ensure_user_spotify_installed

# Keep the official Spicetify CLI available before configuring and applying it.
if [[ ! -x "$SPICETIFY_BIN" ]]; then
    bash "$PROJECT_DIR/scripts/install_spicetify.sh"
fi

# Configure the project-owned Spicetify environment, install Marketplace if
# missing, and apply it when the Spotify version/configuration needs patching.
bash "$PROJECT_DIR/scripts/configure_spicetify.sh"

ok "Launching Spotify $TARGET_SPOTIFY_VERSION from the Goinfre user installation."
exec flatpak run --user "$APP_ID" "$@"
