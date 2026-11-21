#!/usr/bin/env bash
# Single entry point: initialize, recover, configure, apply, then launch.
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

# Only one setup/launch controller may modify this user installation at a time.
exec 9>"$SETUP_DIR/.launch.lock"
flock -n 9 || die "Another Spotify setup/launch process is already running."

# Preserve the user's current themes/extensions/apps before setup can change
# their Spicetify config. The snapshot is ignored by this public repository.
"$PROJECT_DIR/backup.sh"

if ! spotify_is_installed; then
    info "Spotify is not installed in this project's user Flatpak directory."
    "$PROJECT_DIR/scripts/recover_known_good.sh" --yes
else
    info "Found a user-installed Spotify build: $(flatpak info --user --show-version "$APP_ID")"
fi

ensure_user_spotify_installed
if [[ ! -x "$SPICETIFY_BIN" ]]; then
    "$PROJECT_DIR/scripts/install_spicetify.sh"
fi

SPOTIFY_PATH="$(spotify_install_path)" || die "Could not locate the user Spotify deployment."
[[ -d "$SPOTIFY_PATH" && -w "$SPOTIFY_PATH" ]] || die "Spotify's user deployment is missing or not writable: $SPOTIFY_PATH"

# First launch creates the profile and prefs. Let the user sign in, then rerun
# this same entry point; no setup state is marked complete prematurely.
if [[ ! -s "$PREFS_PATH" ]]; then
    info "Starting Spotify once so it can create your profile. Sign in, close Spotify, then run ./launch.sh again."
    exec flatpak run --user "$APP_ID" "$@"
fi

if flatpak ps --columns=application 2>/dev/null | grep -Fxq "$APP_ID"; then
    die "Spotify is still running. Close it completely, then run ./launch.sh again so Spicetify can safely patch it."
fi

if ! spicetify_config_matches_install; then
    info "Configuring Spicetify paths for this user installation."
    spicetify config spotify_path "$SPOTIFY_PATH" prefs_path "$PREFS_PATH"
fi

if ! spicetify_has_backup; then
    info "Creating the missing/version-matched vanilla backup. Existing valid backups are never reset."
    spicetify backup
fi

if ! spicetify_has_customizations && repository_backup_exists; then
    info "Restoring the repository's portable customizations."
    "$PROJECT_DIR/restore.sh" --yes
fi

if ! marketplace_is_installed; then
    "$PROJECT_DIR/scripts/install_marketplace.sh"
fi

if ! spicetify_is_applied; then
    info "Applying Spicetify."
    spicetify apply
fi

"$PROJECT_DIR/scripts/verify.sh" >/dev/null
ok "Spotify and Spicetify are ready."
exec flatpak run --user "$APP_ID" "$@"
