#!/usr/bin/env bash
# Single entry point: install the compatible Spotify build, then launch it.
set -Eeuo pipefail

show_help() {
    cat <<'EOF'
Spotify + Spicetify setup

Usage:
  ./launch.sh [options]

Options:
  -h, --help    Show this help and exit without installing or launching anything.

Description:
  Installs or verifies the pinned Spotify build and compatible Mesa runtime,
  configures Spicetify and Marketplace, applies Spicetify when needed, then
  launches Spotify.

Examples:
  ./launch.sh
  ./launch.sh --help

Any other arguments are passed to Spotify.
EOF
}

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
esac

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

exec 9>"$SETUP_DIR/.launch.lock"
flock -n 9 || die "Another Spotify setup/launch process is already running."

if spotify_is_installed; then
    info "Current Goinfre Spotify: $(spotify_installed_version || printf unknown)"
else
    info "Spotify is not installed in the project-owned user Flatpak directory."
fi

bash "$PROJECT_DIR/scripts/install_legacy_spotify.sh"
ensure_user_spotify_installed

if [[ ! -x "$SPICETIFY_BIN" ]]; then
    bash "$PROJECT_DIR/scripts/install_spicetify.sh"
fi

if bash "$PROJECT_DIR/scripts/configure_spicetify.sh"; then
    :
else
    configure_status=$?
    if [[ "$configure_status" != "10" ]]; then
        exit "$configure_status"
    fi
    info "Opening pinned Spotify once to initialize its profile. Sign in if needed, then close Spotify; setup will continue automatically."
    flatpak run --user "$APP_ID" "$@"
    bash "$PROJECT_DIR/scripts/configure_spicetify.sh"
fi

ok "Launching Spotify $TARGET_SPOTIFY_VERSION from the Goinfre user installation."
exec flatpak run --user "$APP_ID" "$@"
