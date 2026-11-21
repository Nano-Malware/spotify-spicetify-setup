#!/usr/bin/env bash
# Collect a safe, read-only report for Spotify/Flatpak/Spicetify troubleshooting.
# This script does not install, remove, update, or modify anything.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_ID="com.spotify.Client"
KNOWN_GOOD_SYSTEM_COMMIT="d5724652e6dbee2d912d4da426b55d6d16364c405d4f271ca2f04855a7046366"

SETUP_DIR="${SPOTIFY_SETUP_DIR:-}"
if [[ -z "$SETUP_DIR" && -f "$PROJECT_DIR/.setup-dir" ]]; then
    IFS= read -r SETUP_DIR < "$PROJECT_DIR/.setup-dir" || true
fi
if [[ -z "$SETUP_DIR" ]]; then
    SETUP_DIR="/goinfre/${USER:-$(id -un)}/spotify-spicetify"
fi
export FLATPAK_USER_DIR="$SETUP_DIR/flatpak"

section() { printf '\n=== %s ===\n' "$1"; }
show_value() { printf '%-30s %s\n' "$1" "$2"; }
flatpak_info_value() {
    local scope="$1" ref="$2" option="$3" value
    if value="$(flatpak info "$scope" "$option" "$ref" 2>/dev/null)"; then
        printf '%s' "$value"
    else
        printf 'not installed / unavailable'
    fi
}

section "Host"
show_value "Distribution" "$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-unknown}")"
show_value "Kernel" "$(uname -r)"
show_value "Architecture" "$(uname -m)"
show_value "glibc" "$(ldd --version 2>/dev/null | head -n 1 || printf unknown)"
show_value "Flatpak" "$(flatpak --version 2>/dev/null || printf unavailable)"
show_value "Git" "$(git --version 2>/dev/null || printf unavailable)"

amd_gpu="no"
for vendor_file in /sys/class/drm/card[0-9]*/device/vendor; do
    [[ -r "$vendor_file" ]] || continue
    if [[ "$(cat "$vendor_file" 2>/dev/null || true)" == "0x1002" ]]; then
        amd_gpu="yes"
        break
    fi
done
show_value "AMD GPU detected via sysfs" "$amd_gpu"
show_value "Flatpak GL driver choices" "$(flatpak --gl-drivers 2>/dev/null | tr '\n' ' ' || printf unavailable)"

section "Storage"
show_value "Project directory" "$PROJECT_DIR"
show_value "Selected setup directory" "$SETUP_DIR"
df -h "$HOME" "$SETUP_DIR" 2>/dev/null || true
if [[ -d "$HOME/.var/app/$APP_ID" ]]; then
    du -sh "$HOME/.var/app/$APP_ID" 2>/dev/null || true
else
    show_value "Spotify home profile" "not created"
fi

section "System Spotify"
show_value "Installed" "$(flatpak info --system "$APP_ID" >/dev/null 2>&1 && printf yes || printf no)"
show_value "Version" "$(flatpak info --system "$APP_ID" 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || true)"
show_value "Commit" "$(flatpak_info_value --system "$APP_ID" --show-commit)"
show_value "Runtime" "$(flatpak_info_value --system "$APP_ID" --show-runtime)"
show_value "System Mesa 24.08" "$(flatpak info --system org.freedesktop.Platform.GL.default//24.08 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || printf not-installed)"
show_value "System Mesa 25.08" "$(flatpak info --system org.freedesktop.Platform.GL.default//25.08 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || printf not-installed)"

section "Goinfre user Spotify"
show_value "Flatpak user directory" "$FLATPAK_USER_DIR"
show_value "Installed" "$(flatpak info --user "$APP_ID" >/dev/null 2>&1 && printf yes || printf no)"
show_value "Version" "$(flatpak info --user "$APP_ID" 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || true)"
show_value "Commit" "$(flatpak_info_value --user "$APP_ID" --show-commit)"
show_value "Runtime" "$(flatpak_info_value --user "$APP_ID" --show-runtime)"
show_value "User Mesa 24.08" "$(flatpak info --user org.freedesktop.Platform.GL.default//24.08 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || printf not-installed)"
show_value "User Mesa 25.08" "$(flatpak info --user org.freedesktop.Platform.GL.default//25.08 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || printf not-installed)"

section "Known-good 24.08 recovery source"
if flatpak remote-info --user --commit="$KNOWN_GOOD_SYSTEM_COMMIT" flathub "$APP_ID" >/dev/null 2>&1; then
    show_value "Pinned commit on Flathub" "available"
else
    show_value "Pinned commit on Flathub" "not available through current user remote"
fi
if [[ -r /var/lib/flatpak/repo/config && -x /usr/bin/flatpak ]]; then
    show_value "System Flatpak repo config" "readable"
else
    show_value "System Flatpak repo config" "not readable"
fi
show_value "System app commit matches baseline" "$([[ "$(flatpak info --system --show-commit "$APP_ID" 2>/dev/null || true)" == "$KNOWN_GOOD_SYSTEM_COMMIT" ]] && printf yes || printf no)"

section "Spicetify"
if [[ -x "$SETUP_DIR/bin/spicetify" ]]; then
    show_value "Spicetify version" "$("$SETUP_DIR/bin/spicetify" --version 2>/dev/null || printf failed)"
else
    show_value "Spicetify" "not installed in selected setup directory"
fi
show_value "Spicetify config directory" "$SETUP_DIR/xdg-config/spicetify"
if [[ -s "$HOME/.var/app/$APP_ID/config/spotify/prefs" ]]; then
    show_value "Spotify prefs file" "present (contents intentionally not displayed)"
else
    show_value "Spotify prefs file" "missing or empty"
fi

printf '\nThis report intentionally excludes Spotify prefs contents, credentials, cookies, tokens, and session data.\n'
