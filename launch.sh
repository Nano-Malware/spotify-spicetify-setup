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
# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh"

# Recheck the host and selected storage on every run. This also handles
# machines where the repository is copied to a different computer.
bash "$PROJECT_DIR/scripts/detect.sh"
init_paths

require_command flatpak
require_command flock
require_command curl
require_command sha256sum
require_command awk
require_command grep

exec 9>"$SETUP_DIR/.launch.lock"
flock -n 9 || die "Another Spotify setup/launch process is already running."

# Recover the Spotify profile filesystem before starting Flatpak.
cleanup_spotify_cache_if_low_space

if spotify_is_installed; then
    info "Current project Spotify: $(spotify_installed_version || printf unknown)"
else
    info "Spotify is not installed in the project-owned user Flatpak directory."
fi

bash "$PROJECT_DIR/scripts/install_legacy_spotify.sh"
ensure_user_spotify_installed

# The installer is idempotent and also upgrades an older project-owned CLI
# to the exact release pinned by common.sh.
bash "$PROJECT_DIR/scripts/install_spicetify.sh"

if bash "$PROJECT_DIR/scripts/configure_spicetify.sh"; then
    :
else
    configure_status=$?
    if [[ "$configure_status" != "10" ]]; then
        die "Spicetify configuration failed with exit status $configure_status. Review the error above."
    fi

    info "Opening pinned Spotify once to initialize its profile. Sign in if needed, then close Spotify; setup will continue automatically."
    if flatpak run --user "$APP_ID" "$@"; then
        :
    else
        launch_status=$?
        die "Spotify exited with status $launch_status during first-run profile initialization. Run 'flatpak run --user $APP_ID' manually to see the Flatpak/Spotify error, fix it, then rerun ./launch.sh."
    fi

    if bash "$PROJECT_DIR/scripts/configure_spicetify.sh"; then
        :
    else
        configure_status=$?
        if [[ "$configure_status" == "10" ]]; then
            die "Spotify closed without recording the pinned build in its preferences. Open it manually with 'flatpak run --user $APP_ID', wait for the main window, close it normally, then rerun ./launch.sh."
        fi
        die "Spicetify configuration failed after Spotify's first launch (exit status $configure_status). Review the error above."
    fi
fi

ok "Launching Spotify $TARGET_SPOTIFY_VERSION from the project-owned user installation."
exec flatpak run --user "$APP_ID" "$@"
