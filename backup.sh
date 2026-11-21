#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$PROJECT_DIR/scripts/common.sh"
init_paths
require_command awk
require_command find
require_command cp
require_command mv

# This snapshot is intentionally outside the public repo's tracked files.
# It can later become the working tree of a separate private Git repository.
SNAPSHOT_DIR="$PROJECT_DIR/backup/profile"
LEGACY_CONFIG_DIR="$HOME/.config/spicetify"
mkdir -p "$SNAPSHOT_DIR"
STAGE_ROOT="$(mktemp -d "$SNAPSHOT_DIR/.backup-tmp.XXXXXX")"
trap 'rm -rf -- "$STAGE_ROOT"' EXIT

backup_directory() {
    local name="$1"
    local source_dir="$SPICETIFY_CONFIG_DIR/$name"
    local destination="$SNAPSHOT_DIR/$name"
    local staged="$STAGE_ROOT/$name"
    local previous="$STAGE_ROOT/$name.previous"
    local entry
    local count

    # Older Spicetify configurations may still live in ~/.config/spicetify.
    if [[ ! -d "$source_dir" && -d "$LEGACY_CONFIG_DIR/$name" ]]; then
        source_dir="$LEGACY_CONFIG_DIR/$name"
    fi

    if [[ ! -d "$source_dir" ]]; then
        info "No $name directory found; leaving any previous snapshot unchanged."
        return 0
    fi

    mkdir -p "$staged"
    if [[ "$name" == "CustomApps" ]]; then
        # Marketplace is managed by the setup script and can be reinstalled.
        while IFS= read -r -d '' entry; do
            [[ "${entry##*/}" == "marketplace" ]] && continue
            cp -a -- "$entry" "$staged/"
        done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)
    else
        cp -a -- "$source_dir/." "$staged/"
    fi

    # Replace each snapshot directory only after its new copy is complete.
    if [[ -e "$destination" ]]; then
        mv -- "$destination" "$previous"
    fi
    if ! mv -- "$staged" "$destination"; then
        [[ ! -e "$previous" ]] || mv -- "$previous" "$destination"
        die "Could not replace the $name snapshot; the previous copy was restored."
    fi
    rm -rf -- "$previous"

    count="$(find "$destination" -type f | wc -l | tr -d ' ')"
    ok "Backed up $name ($count files)"
}

backup_directory Themes
backup_directory Extensions
backup_directory CustomApps

CONFIG_SOURCE="$SPICETIFY_CONFIG_FILE"
if [[ ! -f "$CONFIG_SOURCE" && -f "$LEGACY_CONFIG_DIR/config-xpui.ini" ]]; then
    CONFIG_SOURCE="$LEGACY_CONFIG_DIR/config-xpui.ini"
fi

if [[ -f "$CONFIG_SOURCE" ]]; then
    # Keep portable settings only. Exclude machine paths, launch flags, and
    # Spicetify's local vanilla-backup metadata.
    awk '
        /^\[[[:space:]]*Backup[[:space:]]*\][[:space:]]*$/ { exit }
        /^[[:space:]]*(spotify_path|prefs_path|spotify_launch_flags)[[:space:]]*=/ { next }
        { print }
    ' "$CONFIG_SOURCE" > "$STAGE_ROOT/config-xpui.ini"
    mv -f -- "$STAGE_ROOT/config-xpui.ini" "$SNAPSHOT_DIR/config-xpui.ini"
    ok "Backed up portable Spicetify settings"
else
    warn "Spicetify config was not found; leaving any previous config snapshot unchanged."
fi

# These files are safe defaults for the separate private configuration repo.
cat > "$SNAPSHOT_DIR/.gitignore" <<'EOF'
# Never store Spotify account/session data
prefs
*.prefs
.cookies
*.cookie
*.token
.env
.env.*
*credentials*
*secret*

# Generated state and local caches
Backup/
.backup-tmp.*/
Cache/
cache/
*.db
*.sqlite
*.sqlite3
*.log
.DS_Store
*.swp
*.swo
EOF

cat > "$SNAPSHOT_DIR/README.md" <<'EOF'
# Personal Spicetify Configuration

Private backup of personal Spicetify customizations.

Contains:
- Custom themes
- Custom extensions
- Custom apps (Marketplace is installed separately)
- Portable Spicetify settings

Spotify prefs, login sessions, cookies, tokens, caches, and the vanilla Spotify
application backup are intentionally excluded.

This folder is ignored by the public setup repository. It is intended to be
used as the working tree of a separate **private** GitHub repository.
Review the files and third-party licenses before committing them.
EOF

printf 'Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SNAPSHOT_DIR/backup-date.txt"

ok "Personal Spicetify backup is ready at:"
printf '  %s\n' "$SNAPSHOT_DIR"
printf '\nNo Git repository was created, and nothing was committed or pushed.\n'
printf 'Review the snapshot before creating or pushing a private repository.\n'
