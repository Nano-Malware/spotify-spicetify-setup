#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths
require_spicetify
ensure_user_spotify_installed

SPOTIFY_PATH="$(spotify_install_path)" || die "Could not determine Spotify's installation path."
[[ -d "$SPOTIFY_PATH" ]] || die "Spotify application files are missing."
[[ -w "$SPOTIFY_PATH" ]] || die "Spotify application files are not writable."
[[ -s "$PREFS_PATH" ]] || warn "Spotify prefs file is missing or empty: $PREFS_PATH"

printf '\n'
ok "Environment check passed."
printf '  Spotify Flatpak: %s\n' "$(flatpak info --user --show-ref "$APP_ID")"
printf '  Spicetify:       %s\n' "$("$SPICETIFY_BIN" --version)"
printf '  Install root:    %s\n' "$SETUP_DIR"
printf '  Flatpak data:    %s\n' "$FLATPAK_USER_DIR"
printf '  Spicetify data:  %s\n' "$SPICETIFY_CONFIG_DIR"
printf '  Spotify files:   %s\n' "$SPOTIFY_PATH"
printf '  Spotify prefs:   %s\n' "$PREFS_PATH"
printf '\n'
