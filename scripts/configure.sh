#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths
require_command flatpak
require_spicetify
ensure_user_spotify_installed

SPOTIFY_PATH="$(spotify_install_path)" || die "Could not locate the user-installed Spotify files."
[[ -d "$SPOTIFY_PATH" ]] || die "Spotify's files are missing: $SPOTIFY_PATH"
[[ -w "$SPOTIFY_PATH" ]] || die "Spotify's directory is not writable by your account: $SPOTIFY_PATH"

if [[ ! -s "$PREFS_PATH" ]]; then
    warn "Spotify's prefs file does not exist yet: $PREFS_PATH"
    info "Starting your user-installed Spotify so it can create its profile..."
    mkdir -p "$SETUP_DIR/logs" "$HOME/.var/app/$APP_ID/config/spotify"
    (flatpak run --user "$APP_ID" >"$SETUP_DIR/logs/spotify-first-run.log" 2>&1 &) || true
    printf '\nLog in to Spotify, leave it open for at least 60 seconds, then return here.\n'
    read -r -p "Press Enter when Spotify is ready... "
fi

[[ -s "$PREFS_PATH" ]] || die "Spotify prefs file is still missing or empty. Open Spotify, log in, and run ./scripts/configure.sh again."

if flatpak ps --columns=application 2>/dev/null | grep -Fxq "$APP_ID"; then
    die "Spotify is still running. Close it completely before configuring Spicetify."
fi

spicetify config spotify_path "$SPOTIFY_PATH" prefs_path "$PREFS_PATH"

if spicetify_has_backup; then
    ok "A matching vanilla Spotify backup already exists; preserving it."
else
    info "No matching vanilla backup exists. Creating it once before patching..."
    spicetify backup
fi

ok "Spicetify paths configured."
info "Spotify path: $SPOTIFY_PATH"
info "Prefs path:   $PREFS_PATH"
