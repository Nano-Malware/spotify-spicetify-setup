#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_command uname
require_command df
require_command awk
require_command stat

OS="$(uname -s)"
ARCH="$(uname -m)"
[[ "$OS" == "Linux" ]] || die "This first version supports Linux only (detected: $OS)."
[[ -r /etc/os-release ]] || die "Cannot identify the Linux distribution."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *ubuntu* || "${ID_LIKE:-}" == *debian* ]] || warn "This is not a detected Ubuntu/Debian system; Flatpak support may differ."

info "Distribution: ${PRETTY_NAME:-unknown}"
info "Architecture: $ARCH"
info "Account: ${USER:-$(id -un)}"
info "No administrator privileges will be requested by this project."

if [[ -n "${SPOTIFY_SETUP_DIR:-}" ]]; then
    CANDIDATE="$SPOTIFY_SETUP_DIR"
elif [[ -f "$PROJECT_DIR/.setup-dir" ]]; then
    IFS= read -r CANDIDATE < "$PROJECT_DIR/.setup-dir" || true
    if [[ -z "$CANDIDATE" || ! -d "$(dirname -- "$CANDIDATE")" || ! -w "$(dirname -- "$CANDIDATE")" ]]; then
        CANDIDATE=""
    fi
else
    CANDIDATE=""
fi

if [[ -z "$CANDIDATE" ]]; then
    if [[ -d /goinfre && -w /goinfre ]]; then
        CANDIDATE="/goinfre/${USER:-$(id -un)}/spotify-spicetify"
    else
        CANDIDATE="$HOME/.local/share/spotify-spicetify"
    fi
fi

mkdir -p "$CANDIDATE" 2>/dev/null || die "Cannot create the chosen setup directory: $CANDIDATE"
[[ -w "$CANDIDATE" ]] || die "Chosen setup directory is not writable: $CANDIDATE"

AVAILABLE_KB="$(df -Pk "$CANDIDATE" | awk 'NR==2 {print $4}')"
[[ "$AVAILABLE_KB" =~ ^[0-9]+$ ]] || die "Could not determine free disk space for $CANDIDATE"
MINIMUM_KB=$((5 * 1024 * 1024))
if (( AVAILABLE_KB < MINIMUM_KB )); then
    AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))
    die "Only about ${AVAILABLE_GB} GiB is free at $CANDIDATE; at least 5 GiB is required. Choose a writable mounted drive with SPOTIFY_SETUP_DIR=/path/to/folder ./install.sh. Nothing was installed."
fi

printf '%s\n' "$CANDIDATE" > "$PROJECT_DIR/.setup-dir"
export SPOTIFY_SETUP_DIR="$CANDIDATE"
export FLATPAK_USER_DIR="$CANDIDATE/flatpak"
mkdir -p "$FLATPAK_USER_DIR"

AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))
ok "Setup location: $CANDIDATE"
ok "Free space available: approximately ${AVAILABLE_GB} GiB"
HOME_AVAILABLE_KB="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
if [[ "$HOME_AVAILABLE_KB" =~ ^[0-9]+$ ]] && (( HOME_AVAILABLE_KB < 1024 * 1024 )); then
    HOME_AVAILABLE_MB=$((HOME_AVAILABLE_KB / 1024))
    warn "Your home filesystem has only about ${HOME_AVAILABLE_MB} MiB free. Spotify's sandbox profile/cache stays under ~/.var/app/$APP_ID by default and may consume home space. The installer will not move or symlink your login data."
fi
if [[ "$CANDIDATE" == /goinfre/* ]]; then
    warn "/goinfre may be temporary or cleaned by the campus. Keep this Git repository and your customization backup outside Goinfre."
fi
