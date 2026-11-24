#!/usr/bin/env bash
# Collect a safe, read-only report for Spotify/Flatpak/graphics troubleshooting.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

SETUP_DIR="$(setup_dir_candidate)"
export FLATPAK_USER_DIR="$SETUP_DIR/flatpak"

section() { printf '\n=== %s ===\n' "$1"; }
show_value() { printf '%-32s %s\n' "$1" "$2"; }
info_value() {
    local scope="$1" ref="$2" option="$3" value
    if value="$(flatpak info "$scope" "$option" "$ref" 2>/dev/null)"; then
        printf '%s' "$value"
    else
        printf 'not installed / unavailable'
    fi
}
version_value() {
    local scope="$1" ref="$2"
    flatpak info "$scope" "$ref" 2>/dev/null |
        awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}'
}

section "Host"
show_value "Distribution" "$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-unknown}")"
show_value "Kernel" "$(uname -r)"
show_value "Architecture" "$(uname -m)"
show_value "Flatpak" "$(flatpak --version 2>/dev/null || printf unavailable)"
show_value "AMD GPU detected" "$(
    found=no
    for vendor_file in /sys/class/drm/card[0-9]*/device/vendor; do
        [[ -r "$vendor_file" ]] || continue
        if [[ "$(/bin/cat "$vendor_file" 2>/dev/null || true)" == "0x1002" ]]; then
            found=yes
            break
        fi
    done
    printf '%s' "$found"
)"
show_value "Flatpak GL driver choices" "$(flatpak --gl-drivers 2>/dev/null | tr '\n' ' ' || printf unavailable)"

section "Storage"
show_value "Project directory" "$PROJECT_DIR"
show_value "Selected setup directory" "$SETUP_DIR"
df -h "$HOME" "$SETUP_DIR" 2>/dev/null || true
show_value "Spotify profile" "$([[ -d "$HOME/.var/app/$APP_ID" ]] && printf present || printf not-created)"

section "System Spotify (left untouched)"
show_value "Version" "$(version_value --system "$APP_ID" || true)"
show_value "Commit" "$(info_value --system "$APP_ID" --show-commit)"
show_value "Runtime" "$(info_value --system "$APP_ID" --show-runtime)"
show_value "System Mesa 24.08" "$(version_value --system org.freedesktop.Platform.GL.default//24.08 || true)"
show_value "System Mesa 25.08" "$(version_value --system org.freedesktop.Platform.GL.default//25.08 || true)"

section "Project-owned user Spotify"
show_value "Flatpak user directory" "$FLATPAK_USER_DIR"
show_value "Installed" "$(flatpak info --user "$APP_ID" >/dev/null 2>&1 && printf yes || printf no)"
show_value "Spotify version" "$(version_value --user "$APP_ID" || true)"
show_value "Spotify ref" "$(info_value --user "$APP_ID" --show-ref)"
show_value "Spotify origin" "$(info_value --user "$APP_ID" --show-origin)"
show_value "Expected Spotify version" "$TARGET_SPOTIFY_VERSION"
show_value "Runtime" "$(info_value --user "$APP_ID" --show-runtime)"
show_value "Mesa 24.08" "$(version_value --user org.freedesktop.Platform.GL.default//24.08 || true)"
show_value "Mesa 24.08 extra" "$(version_value --user org.freedesktop.Platform.GL.default//24.08extra || true)"
show_value "Mesa 25.08 (not target)" "$(version_value --user org.freedesktop.Platform.GL.default//25.08 || true)"
show_value "Masked refs" "$(flatpak mask --user 2>/dev/null | tr '\n' ' ' || true)"

section "Spicetify CLI"
if [[ -x "$SETUP_DIR/bin/spicetify" ]]; then
    show_value "Version" "$("$SETUP_DIR/bin/spicetify" --version 2>/dev/null || printf failed)"
else
    show_value "Installed" "no"
fi

printf '\nThis report intentionally excludes Spotify preferences, credentials, cookies, tokens, and session data.\n'
