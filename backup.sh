#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$PROJECT_DIR/scripts/common.sh"
init_paths
require_spicetify

SNAPSHOT_DIR="$PROJECT_DIR/backup/profile"
mkdir -p "$SNAPSHOT_DIR"

for name in Themes Extensions CustomApps; do
    source_dir="$SPICETIFY_CONFIG_DIR/$name"
    destination="$SNAPSHOT_DIR/$name"
    if [[ -d "$source_dir" ]]; then
        tmp_destination="$SNAPSHOT_DIR/.$name.tmp"
        rm -rf -- "$tmp_destination"
        mkdir -p "$tmp_destination"
        cp -a "$source_dir/." "$tmp_destination/"
        rm -rf -- "$destination"
        mv -- "$tmp_destination" "$destination"
        ok "Backed up $name"
    else
        info "No $name directory exists; preserving any existing repository snapshot."
    fi
done

if [[ -f "$SPICETIFY_CONFIG_FILE" ]]; then
    # Do not put machine-specific install paths or Spicetify's machine-specific
    # vanilla-app backup metadata into the portable profile.
    tmp_config="$SNAPSHOT_DIR/.config-xpui.ini.tmp"
    awk '
        /^\[Backup\][[:space:]]*$/ { exit }
        /^[[:space:]]*(spotify_path|prefs_path|spotify_launch_flags)[[:space:]]*=/ { next }
        { print }
    ' "$SPICETIFY_CONFIG_FILE" > "$tmp_config"
    mv -f -- "$tmp_config" "$SNAPSHOT_DIR/config-xpui.ini"
fi

cat > "$SNAPSHOT_DIR/README.txt" <<'TXT'
Portable Spicetify customization snapshot.
Contains Themes, Extensions, CustomApps, and a sanitized Spicetify config.
Does NOT contain Spotify prefs, login credentials, session tokens, Spotify cache,
or Spicetify's vanilla Spotify binary backup.
Review third-party theme/extension licenses before publishing this snapshot.
TXT

printf '%s\n' "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SNAPSHOT_DIR/backup-date.txt"
ok "Portable backup saved to $SNAPSHOT_DIR"
printf 'Review the files, then commit them with Git if you want them stored on GitHub.\n'
