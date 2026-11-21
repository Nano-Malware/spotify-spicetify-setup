#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$PROJECT_DIR/scripts/common.sh"
init_paths
require_spicetify

SNAPSHOT_DIR="$PROJECT_DIR/backup/profile"
[[ -d "$SNAPSHOT_DIR" ]] || die "No backup/profile directory found in this repository."

printf 'This will replace your current Spicetify Themes, Extensions, CustomApps, and config with the repository snapshot.\n'
read -r -p "Continue? [y/N] " answer
[[ "$answer" == [yY] ]] || { info "Restore cancelled."; exit 0; }

mkdir -p "$SPICETIFY_CONFIG_DIR"
for name in Themes Extensions CustomApps; do
    source_dir="$SNAPSHOT_DIR/$name"
    destination="$SPICETIFY_CONFIG_DIR/$name"
    if [[ -d "$source_dir" ]]; then
        rm -rf -- "$destination"
        mkdir -p "$destination"
        cp -a "$source_dir/." "$destination/"
        ok "Restored $name"
    fi
done

if [[ -f "$SNAPSHOT_DIR/config-xpui.ini" ]]; then
    cp "$SNAPSHOT_DIR/config-xpui.ini" "$SPICETIFY_CONFIG_FILE"
fi

SPOTIFY_PATH="$(spotify_install_path)" || die "Could not determine the current user-installed Spotify path."
[[ -s "$PREFS_PATH" ]] || die "Spotify prefs are missing. Launch Spotify, log in, then run ./restore.sh again."

spicetify config spotify_path "$SPOTIFY_PATH" prefs_path "$PREFS_PATH"
info "Close Spotify completely before applying the restored customization."
read -r -p "Press Enter after Spotify is closed... "
spicetify apply
ok "Customization restored and applied."
