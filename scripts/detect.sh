#!/usr/bin/env bash
# Detect the host and choose a safe project-owned storage location.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_command uname
require_command df
require_command awk

OS="$(uname -s)"
ARCH="$(uname -m)"
[[ "$OS" == "Linux" ]] || die "This first version supports Linux only (detected: $OS)."
[[ "$ARCH" == "x86_64" ]] || die "This Spotify package is built for x86_64, not $ARCH."
[[ -r /etc/os-release ]] || die "Cannot identify the Linux distribution."
# shellcheck source=/etc/os-release
source /etc/os-release
[[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *ubuntu* || "${ID_LIKE:-}" == *debian* ]] ||
    warn "This is not a detected Ubuntu/Debian system; Flatpak support may differ."

info "Distribution: ${PRETTY_NAME:-unknown}"
info "Architecture: $ARCH"
info "Account: ${USER:-$(id -un)}"
info "No administrator privileges will be requested by this project."

minimum_kb=$((5 * 1024 * 1024))
home_candidate="$HOME/.local/share/spotify-spicetify"
candidate="$(setup_dir_candidate)"

available_kb() {
    df -Pk "$1" | awk 'NR == 2 { print $4; exit }'
}

prepare_candidate() {
    mkdir -p "$1" 2>/dev/null || return 1
    [[ -w "$1" ]] || return 1
    local free
    free="$(available_kb "$1")" || return 1
    [[ "$free" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$free"
}

if ! candidate_kb="$(prepare_candidate "$candidate")"; then
    if [[ -n "${SPOTIFY_SETUP_DIR:-}" ]]; then
        die "The explicitly selected setup directory is not writable: $candidate."
    elif setup_has_pinned_install "$candidate"; then
        die "The existing Spotify installation is not writable at $candidate. It was not moved or duplicated; restore write access or set SPOTIFY_SETUP_DIR to that same installation path."
    elif [[ "$candidate" != "$home_candidate" ]] &&
         candidate_kb="$(prepare_candidate "$home_candidate")"; then
        candidate="$home_candidate"
        warn "The preferred setup directory is not writable. Falling back to $candidate."
    else
        die "Cannot create or write to the selected setup directory: $candidate. Choose another writable path with SPOTIFY_SETUP_DIR=/path/to/folder ./launch.sh."
    fi
fi

if (( candidate_kb < minimum_kb )); then
    if setup_has_pinned_install "$candidate"; then
        candidate_gb=$((candidate_kb / 1024 / 1024))
        warn "The existing pinned installation has only about ${candidate_gb} GiB free at $candidate. Keeping it in place to avoid silently creating a second installation; free at least 5 GiB before updating or repairing it."
    else
        home_kb="$(prepare_candidate "$home_candidate" || true)"
        if [[ "$candidate" != "$home_candidate" &&
              "$home_kb" =~ ^[0-9]+$ ]] && (( home_kb >= minimum_kb )); then
            candidate="$home_candidate"
            candidate_kb="$home_kb"
            warn "The preferred storage location has less than 5 GiB free. Falling back to $candidate."
        else
            available_gb=$((candidate_kb / 1024 / 1024))
            die "Only about ${available_gb} GiB is free at $candidate; a new installation needs at least 5 GiB. Free space or choose a writable mounted drive with SPOTIFY_SETUP_DIR=/path/to/folder ./launch.sh. Nothing was installed."
        fi
    fi
fi

printf '%s\n' "$candidate" > "$PROJECT_DIR/.setup-dir"
export SPOTIFY_SETUP_DIR="$candidate"
export FLATPAK_USER_DIR="$candidate/flatpak"
mkdir -p "$FLATPAK_USER_DIR"

available_gb=$((candidate_kb / 1024 / 1024))
ok "Setup location: $candidate"
ok "Free space available: approximately ${available_gb} GiB"

home_kb="$(available_kb "$HOME" 2>/dev/null || true)"
if [[ "$home_kb" =~ ^[0-9]+$ ]] && (( home_kb < 1024 * 1024 )); then
    home_mb=$((home_kb / 1024))
    warn "Your home filesystem has only about ${home_mb} MiB free. Spotify's profile/cache stays under ~/.var/app/$APP_ID and may consume home space. The installer will not move or symlink your login data."
fi
if [[ "$candidate" == /goinfre/* ]]; then
    warn "/goinfre may be temporary or cleaned by campus policy. Keep this Git repository outside Goinfre."
fi
