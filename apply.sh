#!/usr/bin/env bash
# Apply Spicetify only to this project's Goinfre-backed user Spotify install.
# This wrapper deliberately avoids the system-wide Spicetify configuration.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh"
init_paths
require_command flatpak
require_spicetify
ensure_user_spotify_installed

APP_LOCATION="$(spotify_install_location)" || die "Could not locate the user Spotify deployment."
case "${APP_LOCATION%/}/" in
    "$FLATPAK_USER_DIR/app/$APP_ID/"*) ;;
    *) die "Refusing to patch an app outside this project's user Flatpak directory: $APP_LOCATION" ;;
esac

SPOTIFY_PATH="$(spotify_install_path)" || die "Could not determine Spotify's application files."
[[ -d "$SPOTIFY_PATH" ]] || die "Spotify application files are missing: $SPOTIFY_PATH"
[[ -w "$SPOTIFY_PATH" ]] || die "Spotify application files are not writable: $SPOTIFY_PATH"
if [[ -d "$SPOTIFY_PATH/Apps" && ! -w "$SPOTIFY_PATH/Apps" ]]; then
    die "Spotify/Apps is not writable: $SPOTIFY_PATH/Apps"
fi
[[ -s "$PREFS_PATH" ]] || die "Spotify prefs are missing. Launch ./launch.sh, sign in, close Spotify, then run ./scripts/configure.sh."

RUNTIME="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null || true)"
printf '\nSpicetify project apply\n'
printf '=======================\n'
printf 'Project config: %s\n' "$SPICETIFY_CONFIG_DIR"
printf 'Project binary: %s\n' "$SPICETIFY_BIN"
printf 'Spotify runtime: %s\n' "${RUNTIME:-unknown}"
printf 'Patch target: %s\n' "$SPOTIFY_PATH"
warn "Quit every Spotify window before continuing. This script refuses to patch the system-wide app."
read -r -p "Press Enter after Spotify is fully closed (Ctrl+C to cancel)... "

info "Applying with this project's Spicetify binary and isolated XDG configuration..."
spicetify apply
ok "Spicetify applied to the Goinfre user Spotify installation."
printf 'Launch it with: %s/launch.sh\n' "$PROJECT_DIR"
