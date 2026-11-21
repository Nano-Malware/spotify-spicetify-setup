#!/usr/bin/env bash
# Shared helpers for the Spotify + Spicetify setup project.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_ID="com.spotify.Client"
KNOWN_GOOD_SPOTIFY_COMMIT="d5724652e6dbee2d912d4da426b55d6d16364c405d4f271ca2f04855a7046366"
KNOWN_GOOD_SPOTIFY_RUNTIME="org.freedesktop.Platform/x86_64/24.08"
FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
SPICETIFY_RELEASE_API="https://api.github.com/repos/spicetify/cli/releases/latest"
MARKETPLACE_INSTALLER_URL="https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1. Install it using your system's approved user-space method or ask your administrator."
}

ini_value() {
    local section="$1"
    local key="$2"
    local file="$3"

    [[ -f "$file" ]] || return 1
    awk -v wanted_section="$section" -v wanted_key="$key" '
        /^[[:space:]]*\[/ {
            active = ($0 == "[" wanted_section "]")
            next
        }
        active {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line ~ ("^" wanted_key "[[:space:]]*=")) {
                sub(/^[^=]*=[[:space:]]*/, "", line)
                sub(/[[:space:]]*$/, "", line)
                print line
                exit
            }
        }
    ' "$file"
}

spotify_is_installed() {
    command -v flatpak >/dev/null 2>&1 || return 1
    flatpak info --user "$APP_ID" >/dev/null 2>&1
}

spotify_is_known_good() {
    local installed_commit
    local installed_runtime

    command -v flatpak >/dev/null 2>&1 || return 1
    installed_commit="$(flatpak info --user --show-commit "$APP_ID" 2>/dev/null)" || return 1
    installed_runtime="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null)" || return 1

    [[ "$installed_commit" == "$KNOWN_GOOD_SPOTIFY_COMMIT" &&
       "$installed_runtime" == "$KNOWN_GOOD_SPOTIFY_RUNTIME" ]]
}

spicetify_has_backup() {
    local backup_version
    local spotify_version
    local backup_file

    [[ -s "$PREFS_PATH" && -f "$SPICETIFY_CONFIG_FILE" ]] || return 1
    [[ -d "$SPICETIFY_BACKUP_DIR" ]] || return 1

    backup_version="$(ini_value Backup version "$SPICETIFY_CONFIG_FILE")"
    spotify_version="$(awk -F= '$1 == "app.last-launched-version" {sub(/^[^=]*=/, ""); print; exit}' "$PREFS_PATH")"
    [[ -n "$backup_version" && "$backup_version" == "$spotify_version" ]] || return 1

    backup_file="$(find "$SPICETIFY_BACKUP_DIR" -maxdepth 1 -type f -name '*.spa' -print -quit 2>/dev/null)"
    [[ -n "$backup_file" ]]
}

spicetify_is_applied() {
    local spotify_path
    local apps_dir
    local spa_file
    local app_dir

    spotify_path="$(spotify_install_path)" || return 1
    apps_dir="$spotify_path/Apps"
    [[ -d "$apps_dir" ]] || return 1

    # Match Spicetify's own status logic: applied means app directories exist
    # and no original .spa archives remain directly inside Apps/.
    spa_file="$(find "$apps_dir" -mindepth 1 -maxdepth 1 -type f -name '*.spa' -print -quit 2>/dev/null)"
    app_dir="$(find "$apps_dir" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null)"
    [[ -z "$spa_file" && -n "$app_dir" ]]
}

spicetify_config_matches_install() {
    local spotify_path
    local configured_spotify
    local configured_prefs

    spotify_path="$(spotify_install_path)" || return 1
    configured_spotify="$(ini_value Setting spotify_path "$SPICETIFY_CONFIG_FILE")"
    configured_prefs="$(ini_value Setting prefs_path "$SPICETIFY_CONFIG_FILE")"

    [[ "$configured_spotify" == "$spotify_path" && "$configured_prefs" == "$PREFS_PATH" ]]
}

spicetify_has_customizations() {
    local name
    local entry

    for name in Themes Extensions CustomApps; do
        [[ -d "$SPICETIFY_CONFIG_DIR/$name" ]] || continue
        if [[ "$name" == "CustomApps" ]]; then
            # Marketplace is installed by the launcher; it is not a personal
            # customization and must not block restoring saved custom apps.
            entry="$(find "$SPICETIFY_CONFIG_DIR/$name" -mindepth 1 -maxdepth 1 ! -name marketplace -print -quit 2>/dev/null)"
        else
            entry="$(find "$SPICETIFY_CONFIG_DIR/$name" -mindepth 1 -print -quit 2>/dev/null)"
        fi
        [[ -n "$entry" ]] && return 0
    done
    return 1
}

repository_backup_exists() {
    local name
    local entry
    local snapshot_dir="$PROJECT_DIR/backup/profile"

    [[ -d "$snapshot_dir" ]] || return 1
    for name in Themes Extensions CustomApps; do
        [[ -d "$snapshot_dir/$name" ]] || continue
        entry="$(find "$snapshot_dir/$name" -mindepth 1 -print -quit 2>/dev/null)"
        [[ -n "$entry" ]] && return 0
    done
    [[ -s "$snapshot_dir/config-xpui.ini" ]]
}

marketplace_is_installed() {
    [[ -d "$SPICETIFY_CONFIG_DIR/CustomApps/marketplace" ]]
}

init_paths() {
    local saved_path=""
    local legacy_backup="$HOME/.local/state/spicetify/Backup"

    if [[ -n "${SPOTIFY_SETUP_DIR:-}" ]]; then
        SETUP_DIR="$SPOTIFY_SETUP_DIR"
    elif [[ -f "$PROJECT_DIR/.setup-dir" ]]; then
        IFS= read -r saved_path < "$PROJECT_DIR/.setup-dir" || true
        SETUP_DIR="$saved_path"
    else
        die "Setup location is not recorded yet. Run ./launch.sh to initialize it."
    fi

    [[ -n "$SETUP_DIR" ]] || die "The saved setup directory is empty. Run ./launch.sh to initialize it."
    mkdir -p "$SETUP_DIR"
    [[ -w "$SETUP_DIR" ]] || die "Setup directory is not writable: $SETUP_DIR"

    export SPOTIFY_SETUP_DIR="$SETUP_DIR"
    export FLATPAK_USER_DIR="$SETUP_DIR/flatpak"
    export XDG_CONFIG_HOME="$SETUP_DIR/xdg-config"
    export XDG_CACHE_HOME="$SETUP_DIR/xdg-cache"
    export XDG_DATA_HOME="$SETUP_DIR/xdg-data"
    export XDG_STATE_HOME="$SETUP_DIR/xdg-state"
    export SPICETIFY_CONFIG="$XDG_CONFIG_HOME/spicetify"
    export SPICETIFY_STATE="$XDG_STATE_HOME/spicetify"
    export PATH="$SETUP_DIR/bin:$PATH"

    BIN_DIR="$SETUP_DIR/bin"
    SPICETIFY_BIN="$BIN_DIR/spicetify"
    SPICETIFY_CONFIG_DIR="$XDG_CONFIG_HOME/spicetify"
    SPICETIFY_CONFIG_FILE="$SPICETIFY_CONFIG_DIR/config-xpui.ini"
    SPICETIFY_BACKUP_DIR="$XDG_STATE_HOME/spicetify/Backup"
    PREFS_PATH="$HOME/.var/app/$APP_ID/config/spotify/prefs"

    mkdir -p "$BIN_DIR" "$SPICETIFY_CONFIG_DIR" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

    # Preserve customizations from the standard Spicetify config location.
    if [[ ! -f "$SPICETIFY_CONFIG_FILE" && -d "$HOME/.config/spicetify" ]]; then
        cp -a "$HOME/.config/spicetify/." "$SPICETIFY_CONFIG_DIR/"
    fi

    # Older project versions let Spicetify put its vanilla backup in ~/.local/state.
    # Copy it once into the Goinfre-backed state directory; never delete the source.
    if [[ ! -d "$SPICETIFY_BACKUP_DIR" && -d "$legacy_backup" ]]; then
        mkdir -p "$SPICETIFY_BACKUP_DIR"
        cp -a "$legacy_backup/." "$SPICETIFY_BACKUP_DIR/"
    fi
}

require_spicetify() {
    [[ -x "$SPICETIFY_BIN" ]] || die "Spicetify CLI is missing at $SPICETIFY_BIN. Run ./launch.sh first."
}

spicetify() {
    require_spicetify
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" SPICETIFY_CONFIG="$SPICETIFY_CONFIG" SPICETIFY_STATE="$SPICETIFY_STATE" "$SPICETIFY_BIN" "$@"
}

spotify_install_location() {
    flatpak info --user --show-location "$APP_ID" 2>/dev/null
}

spotify_install_path() {
    local location
    location="$(spotify_install_location)" || return 1
    printf '%s/files/extra/share/spotify\n' "${location%/}"
}

ensure_user_spotify_installed() {
    flatpak info --user "$APP_ID" >/dev/null 2>&1 || die "Spotify is not installed in the configured user-level Flatpak installation. Run ./launch.sh."
}
