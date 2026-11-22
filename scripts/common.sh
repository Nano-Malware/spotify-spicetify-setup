#!/usr/bin/env bash
# Shared helpers for the Spotify user-space launcher.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_ID="com.spotify.Client"
TARGET_SPOTIFY_VERSION="1.2.52.442.g01893f92"
TARGET_SPOTIFY_RUNTIME="org.freedesktop.Platform/x86_64/24.08"
FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
SPICETIFY_RELEASES_URL="https://github.com/spicetify/cli/releases"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1. Install it using your system's approved user-space method or ask your administrator."
}

run_with_progress() {
    local label="$1"
    shift
    local log_file
    local status_file
    local pid
    local status
    local started
    local elapsed
    local frame=0
    local width=30
    local block=5
    local travel
    local phase
    local position
    local after
    local bar

    log_file="$(mktemp "$SETUP_DIR/.progress.XXXXXX")"
    status_file="$log_file.status"

    (
        set +e
        "$@" >"$log_file" 2>&1
        status=$?
        printf '%s\n' "$status" >"$status_file"
    ) &
    pid=$!

    started=$SECONDS
    travel=$((width - block))

    if [[ -t 2 ]]; then
        while [[ ! -s "$status_file" ]]; do
            phase=$((frame % (travel * 2)))
            if (( phase > travel )); then
                position=$((travel * 2 - phase))
            else
                position="$phase"
            fi
            after=$((position + block))
            printf -v bar '%*s' "$width" ''
            bar="\${bar// /-}"
            bar="\${bar:0:position}#####\${bar:after}"
            elapsed=$((SECONDS - started))
            printf '\r\033[K  \033[1;35m[%s]\033[0m %-38.38s %02d:%02d' \
                "$bar" "$label" "$((elapsed / 60))" "$((elapsed % 60))" >&2
            sleep 0.12
            frame=$((frame + 1))
        done
    fi

    wait "$pid" || true
    status="$(cat "$status_file")"
    elapsed=$((SECONDS - started))

    if [[ -t 2 ]]; then
        if [[ "$status" == "0" ]]; then
            printf '\r\033[K  \033[1;32m[done]\033[0m %-38.38s %02d:%02d\n' \
                "$label" "$((elapsed / 60))" "$((elapsed % 60))" >&2
        else
            printf '\r\033[K  \033[1;31m[fail]\033[0m %-38.38s %02d:%02d\n' \
                "$label" "$((elapsed / 60))" "$((elapsed % 60))" >&2
        fi
    else
        printf '[%s] %s (%02d:%02d)\n' \
            "$([[ "$status" == "0" ]] && printf OK || printf FAIL)" \
            "$label" "$((elapsed / 60))" "$((elapsed % 60))" >&2
    fi

    if [[ "$status" == "0" ]]; then
        cat "$log_file"
    else
        cat "$log_file" >&2
    fi

    rm -f -- "$log_file" "$status_file"
    return "$status"
}

spotify_is_installed() {
    command -v flatpak >/dev/null 2>&1 || return 1
    flatpak info --user "$APP_ID" >/dev/null 2>&1
}

spotify_installed_version() {
    flatpak info --user "$APP_ID" 2>/dev/null |
        awk '/^[[:space:]]*Version:/ {
            sub(/^[[:space:]]*Version:[[:space:]]*/, "")
            print
            exit
        }'
}

spotify_is_target_build() {
    local installed_version
    local installed_runtime
    local installed_ref

    command -v flatpak >/dev/null 2>&1 || return 1
    installed_version="$(spotify_installed_version)" || return 1
    installed_runtime="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null)" || return 1
    installed_ref="$(flatpak info --user --show-ref "$APP_ID" 2>/dev/null)" || return 1

    [[ "$installed_version" == "$TARGET_SPOTIFY_VERSION" &&
       "$installed_runtime" == "$TARGET_SPOTIFY_RUNTIME" &&
       "$installed_ref" == "app/com.spotify.Client/x86_64/stable" ]]
}

init_paths() {
    local saved_path=""

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
    PREFS_PATH="$HOME/.var/app/$APP_ID/config/spotify/prefs"

    mkdir -p "$BIN_DIR" "$SPICETIFY_CONFIG_DIR" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
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
