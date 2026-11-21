#!/usr/bin/env bash
# Install Spotify into the project's user Flatpak directory.
# Prefer the tested build when it is still available; otherwise use Flathub stable.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh"
init_paths
require_command flatpak
require_command awk
require_command grep

REMOTE="flathub"
SYSTEM_REPO="/var/lib/flatpak/repo"
BUNDLE_DIR="$SETUP_DIR/recovery"
BUNDLE="$BUNDLE_DIR/spotify-tested.flatpak"
BUNDLE_TMP="$BUNDLE_DIR/.spotify-tested.$$.flatpak"
trap 'rm -f -- "$BUNDLE_TMP"' EXIT

printf '\nSpotify installation\n'
printf '=====================\n'
printf 'Target user install: %s\n' "$FLATPAK_USER_DIR"

if ! flatpak remotes --user | awk 'NR > 1 {print $1}' | grep -Fxq "$REMOTE"; then
    info "Adding the official Flathub remote to this user installation."
    flatpak remote-add --user --if-not-exists "$REMOTE" "$FLATHUB_URL"
fi

CURRENT_COMMIT="$(flatpak info --user --show-commit "$APP_ID" 2>/dev/null || true)"
CURRENT_RUNTIME="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null || true)"
if [[ -n "$CURRENT_COMMIT" ]]; then
    info "A Spotify installation already exists in this user directory."
    printf 'Current app commit: %s\n' "$CURRENT_COMMIT"
    printf 'Current runtime: %s\n' "${CURRENT_RUNTIME:-unknown}"
else
    CURRENT_COMMIT="not-installed"
    CURRENT_RUNTIME="not-installed"
fi

# Preserve the tested build where it is still obtainable. A clean computer
# must not depend on having another machine's system installation available.
SOURCE="flathub-stable"
if flatpak remote-info --user --commit="$KNOWN_GOOD_SPOTIFY_COMMIT" "$REMOTE" "$APP_ID" >/dev/null 2>&1; then
    SOURCE="flathub-tested"
else
    SYSTEM_COMMIT="$(flatpak info --system --show-commit "$APP_ID" 2>/dev/null || true)"
    if [[ "$(uname -m)" == "x86_64" &&
          "$SYSTEM_COMMIT" == "$KNOWN_GOOD_SPOTIFY_COMMIT" &&
          -r "$SYSTEM_REPO/config" &&
          -d "$SYSTEM_REPO/objects" ]]; then
        SOURCE="system-bundle"
    else
        warn "The older tested Spotify build is not available from Flathub or a matching local system installation."
        info "A fresh installation will use the current Spotify stable package from Flathub from Flathub."
    fi
fi

if [[ "${1:-}" != "--yes" ]]; then
    case "$SOURCE" in
        flathub-tested)
            read -r -p "Install the project's tested Spotify build? [Y/n] " answer
            [[ -z "$answer" || "$answer" == [yY] ]] || { info "Installation cancelled."; exit 0; }
            ;;
        system-bundle)
            read -r -p "Export and install the tested Spotify build from the system repository? [Y/n] " answer
            [[ -z "$answer" || "$answer" == [yY] ]] || { info "Installation cancelled."; exit 0; }
            ;;
        *)
            read -r -p "Install the current Spotify stable package from Flathub from Flathub? [Y/n] " answer
            [[ -z "$answer" || "$answer" == [yY] ]] || { info "Installation cancelled."; exit 0; }
            ;;
    esac
fi

case "$SOURCE" in
    flathub-tested)
        if [[ "$CURRENT_COMMIT" == "not-installed" ]]; then
            info "Installing Spotify and its required Flatpak runtime dependencies."
            flatpak install --user -y "$REMOTE" "$APP_ID"
        fi
        info "Selecting the tested Spotify app build."
        flatpak update --user -y --commit="$KNOWN_GOOD_SPOTIFY_COMMIT" "$APP_ID"
        ;;
    system-bundle)
        mkdir -p "$BUNDLE_DIR"
        info "Exporting the matching system Spotify app as a complete Flatpak bundle."
        # Do not use --from-commit: the destination user OSTree repo is separate.
        flatpak build-bundle --arch=x86_64 --runtime-repo="$FLATHUB_URL" \
            "$SYSTEM_REPO" "$BUNDLE_TMP" "$APP_ID" stable
        [[ -s "$BUNDLE_TMP" ]] || die "The system app bundle export failed."
        mv -f -- "$BUNDLE_TMP" "$BUNDLE"
        info "Installing the app bundle into the project-owned user Flatpak directory."
        flatpak install --user --reinstall -y --bundle "$BUNDLE"
        ;;
    flathub-stable)
        if [[ "$CURRENT_COMMIT" == "not-installed" ]]; then
            info "Installing the current Spotify stable package from Flathub and its runtime dependencies."
            flatpak install --user -y "$REMOTE" "$APP_ID"
        else
            info "Updating this user Spotify installation to the current Flathub stable build."
            flatpak update --user -y "$APP_ID"
        fi
        ;;
esac

DEPLOYED_COMMIT="$(flatpak info --user --show-commit "$APP_ID" 2>/dev/null || true)"
DEPLOYED_RUNTIME="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null || true)"
DEPLOYED_VERSION="$(flatpak info --user --show-version "$APP_ID" 2>/dev/null || true)"
printf '\nInstalled Spotify version: %s\n' "${DEPLOYED_VERSION:-unknown}"
printf 'Installed app commit: %s\n' "${DEPLOYED_COMMIT:-unknown}"
printf 'Installed runtime: %s\n' "${DEPLOYED_RUNTIME:-unknown}"

[[ -n "$DEPLOYED_COMMIT" && -n "$DEPLOYED_RUNTIME" ]] || die "Spotify installation could not be verified."

if [[ "$SOURCE" == "flathub-tested" || "$SOURCE" == "system-bundle" ]]; then
    [[ "$DEPLOYED_COMMIT" == "$KNOWN_GOOD_SPOTIFY_COMMIT" ]] || die "The installed app does not match the tested Spotify build."
    [[ "$DEPLOYED_RUNTIME" == "$KNOWN_GOOD_SPOTIFY_RUNTIME" ]] || die "The installed app does not use the expected tested runtime."
    # Keep this specific known-tested build from being silently replaced.
    flatpak mask --user "$APP_ID"
    ok "The tested Spotify build is installed and protected from automatic replacement."
else
    # Do not mask the current stable branch: let Flatpak receive normal updates.
    ok "The current Spotify stable package from Flathub is installed; normal updates remain enabled."
fi

APP_LOCATION="$(flatpak info --user --show-location "$APP_ID")"
SPOTIFY_PATH="$APP_LOCATION/files/extra/share/spotify"
[[ -d "$SPOTIFY_PATH" ]] || die "Spotify files were not found at $SPOTIFY_PATH"
[[ -w "$SPOTIFY_PATH" ]] || die "The user Spotify deployment is not writable: $SPOTIFY_PATH"

ok "Spotify is ready in the project-owned user Flatpak installation."
