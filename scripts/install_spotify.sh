#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths

require_command flatpak
require_command curl

info "Using this per-user Flatpak installation directory: $FLATPAK_USER_DIR"
mkdir -p "$FLATPAK_USER_DIR"

if ! flatpak remotes --user | awk 'NR > 1 {print $1}' | grep -Fxq flathub; then
    info "Adding Flathub to this Goinfre-backed user installation..."
    flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL"
fi

if flatpak info --user "$APP_ID" >/dev/null 2>&1; then
    ok "Spotify is already installed in this user-level Flatpak installation."
else
    info "Installing Spotify from Flathub without sudo..."
    flatpak install --user -y flathub "$APP_ID"
fi

APP_LOCATION="$(spotify_install_location)" || die "Flatpak installed Spotify, but its deployment location could not be detected."
SPOTIFY_PATH="${APP_LOCATION%/}/files/extra/share/spotify"
[[ -d "$SPOTIFY_PATH" ]] || die "Spotify's application directory was not found at: $SPOTIFY_PATH"

# User-scope deployments should be owned by this user. We only grant the owner
# write permission if needed; no root-owned system installation is modified.
OWNER_UID="$(stat -c '%u' "$SPOTIFY_PATH")"
if [[ "$OWNER_UID" == "$(id -u)" ]]; then
    chmod u+rwX "$SPOTIFY_PATH" || die "Could not make the user-owned Spotify directory writable."
    if [[ -d "$SPOTIFY_PATH/Apps" ]]; then
        chmod -R u+rwX "$SPOTIFY_PATH/Apps" || die "Could not make Spotify/Apps writable."
    fi
else
    warn "Spotify's deployment is owned by UID $OWNER_UID, not your account. This script will not attempt privileged permission changes."
fi

if [[ ! -w "$SPOTIFY_PATH" || ( -d "$SPOTIFY_PATH/Apps" && ! -w "$SPOTIFY_PATH/Apps" ) ]]; then
    die "Spicetify needs write access to the user-installed Spotify directory. This Flatpak deployment is not writable by your account, and this project will not use sudo."
fi

ok "Spotify installed for this user."
info "Spotify application files: $SPOTIFY_PATH"
info "Spotify's own profile/cache remains in: $HOME/.var/app/$APP_ID"
