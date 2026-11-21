#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$PROJECT_DIR/scripts/common.sh"
init_paths
require_spicetify

SNAPSHOT_DIR="$PROJECT_DIR/backup/profile"
[[ -d "$SNAPSHOT_DIR" ]] || die "No backup/profile directory found in this repository."

if [[ "${1:-}" != "--yes" ]]; then
    printf 'This replaces your current Themes, Extensions, CustomApps and portable settings. The live vanilla [Backup] section is preserved.\n'
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" == [yY] ]] || { info "Restore cancelled."; exit 0; }
fi

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
    tmp_config="$(mktemp "$SPICETIFY_CONFIG_DIR/config-xpui.ini.XXXXXX")"
    cp "$SNAPSHOT_DIR/config-xpui.ini" "$tmp_config"

    # Keep the machine-specific live Spicetify vanilla backup metadata.
    if grep -q '^\[Backup\][[:space:]]*$' "$SPICETIFY_CONFIG_FILE" 2>/dev/null; then
        awk '
            /^\[Backup\][[:space:]]*$/ { copying = 1 }
            copying { print }
        ' "$SPICETIFY_CONFIG_FILE" >> "$tmp_config"
    fi
    mv -f -- "$tmp_config" "$SPICETIFY_CONFIG_FILE"
fi

SPOTIFY_PATH="$(spotify_install_path)" || die "Could not determine the current user-installed Spotify path."
[[ -s "$PREFS_PATH" ]] || die "Spotify prefs are missing. Launch Spotify, log in, then run ./restore.sh again."

spicetify config spotify_path "$SPOTIFY_PATH" prefs_path "$PREFS_PATH"
if [[ "${1:-}" != "--yes" ]]; then
    info "Close Spotify completely before applying the restored customization."
    read -r -p "Press Enter after Spotify is closed... "
fi
spicetify apply
ok "Customization restored and applied."
