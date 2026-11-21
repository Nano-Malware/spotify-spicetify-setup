#!/usr/bin/env bash
# Restore the known-working Spotify 24.08 app build to the Goinfre user install.
# This is opt-in, interactive, and never changes the system installation.
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh"
init_paths
require_command flatpak

KNOWN_GOOD_COMMIT="$KNOWN_GOOD_SPOTIFY_COMMIT"
REMOTE="flathub"
SYSTEM_REPO="/var/lib/flatpak/repo"
BUNDLE_DIR="$SETUP_DIR/recovery"
BUNDLE="$BUNDLE_DIR/spotify-known-good.flatpak"
BUNDLE_TMP="$BUNDLE_DIR/.spotify-known-good.$$.flatpak"
trap 'rm -f -- "$BUNDLE_TMP"' EXIT

printf '\nSpotify compatibility recovery\n'
printf '===============================\n'
warn "This changes only the Goinfre user installation. It does not modify the system Spotify app or your Spotify profile."
printf 'Target commit: %s\n' "$KNOWN_GOOD_COMMIT"
printf 'Target install: %s\n' "$FLATPAK_USER_DIR"

if ! flatpak remotes --user | awk 'NR > 1 {print $1}' | grep -Fxq "$REMOTE"; then
    info "Adding Flathub to the Goinfre user installation."
    flatpak remote-add --user --if-not-exists "$REMOTE" "$FLATHUB_URL"
fi

if flatpak info --user "$APP_ID" >/dev/null 2>&1; then
    CURRENT_COMMIT="$(flatpak info --user --show-commit "$APP_ID" 2>/dev/null || true)"
    CURRENT_RUNTIME="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null || true)"
    printf 'Current user app commit: %s\n' "${CURRENT_COMMIT:-unknown}"
    printf 'Current user app runtime: %s\n' "${CURRENT_RUNTIME:-unknown}"
else
    CURRENT_COMMIT="not-installed"
    CURRENT_RUNTIME="not-installed"
    info "No Spotify app is currently installed in this Goinfre user installation."
fi

SOURCE="remote"
if flatpak remote-info --user --commit="$KNOWN_GOOD_COMMIT" "$REMOTE" "$APP_ID" >/dev/null 2>&1; then
    info "The exact known-good app commit is available from Flathub."
else
    SOURCE="system-bundle"
    warn "Flathub no longer exposes the pinned commit to this user remote."
    [[ -r "$SYSTEM_REPO/config" ]] || die "The system Flatpak repository is not readable. Cannot create a local recovery bundle."
    flatpak info --system --show-commit "$APP_ID" 2>/dev/null | grep -Fxq "$KNOWN_GOOD_COMMIT" || die "The system Spotify installation is not at the expected known-good commit. Refusing to export a different build."
    [[ -r "$SYSTEM_REPO/objects" && -x "$SYSTEM_REPO/objects" ]] || die "System OSTree objects are not readable. Repository config alone is not enough to export a bundle."
    mkdir -p "$BUNDLE_DIR"
    info "Exporting the exact known-good system app commit to $BUNDLE"

    # IMPORTANT: do not pass --from-commit here.
    # --from-commit creates a delta that requires its base commit in the
    # destination OSTree repository. The Goinfre user repo is independent
    # from /var/lib/flatpak, so it does not contain that system commit.
    # Omitting --from-commit creates a complete bundle (delta against empty).
    flatpak build-bundle --arch=x86_64 --runtime-repo="$FLATHUB_URL" "$SYSTEM_REPO" "$BUNDLE_TMP" "$APP_ID" stable
    [[ -s "$BUNDLE_TMP" ]] || die "Bundle export did not produce a non-empty file."
    mv -f -- "$BUNDLE_TMP" "$BUNDLE"
    ok "Created a complete standalone bundle."
fi

printf '\nRecovery source: %s\n' "$SOURCE"
printf 'This operation may download the 24.08 runtime and Mesa extensions.\n'
if [[ "${1:-}" != "--yes" ]]; then
    read -r -p "Proceed with recovery of the Goinfre user Spotify? [y/N] " answer
    [[ "$answer" == [yY] ]] || { info "Recovery cancelled; nothing was changed."; exit 0; }
fi

if [[ "$SOURCE" == "remote" ]]; then
    if [[ "$CURRENT_COMMIT" == "not-installed" ]]; then
        info "Installing Spotify into the Goinfre user installation."
        flatpak install --user -y "$REMOTE" "$APP_ID"
    fi
    info "Switching the Goinfre user app to the pinned known-good commit."
    flatpak update --user -y --commit="$KNOWN_GOOD_COMMIT" "$APP_ID"
else
    info "Installing the exported known-good app bundle into the Goinfre user installation."
    flatpak install --user --reinstall -y --bundle "$BUNDLE"
fi

DEPLOYED_COMMIT="$(flatpak info --user --show-commit "$APP_ID" 2>/dev/null || true)"
DEPLOYED_RUNTIME="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null || true)"
printf '\nDeployed app commit: %s\n' "${DEPLOYED_COMMIT:-unknown}"
printf 'Deployed runtime: %s\n' "${DEPLOYED_RUNTIME:-unknown}"
[[ "$DEPLOYED_COMMIT" == "$KNOWN_GOOD_COMMIT" ]] || die "The deployed app commit does not match the known-good baseline. Keep the old system installation; do not run Spicetify apply."
[[ "$DEPLOYED_RUNTIME" == "$KNOWN_GOOD_SPOTIFY_RUNTIME" ]] || die "The app runtime is not the expected 24.08 runtime. Do not proceed to Spicetify yet."

# Prevent an ordinary Flatpak update from silently replacing the tested build.
flatpak mask --user "$APP_ID"

APP_LOCATION="$(flatpak info --user --show-location "$APP_ID")"
SPOTIFY_PATH="$APP_LOCATION/files/extra/share/spotify"
[[ -d "$SPOTIFY_PATH" ]] || die "Spotify files were not found at $SPOTIFY_PATH"
[[ -w "$SPOTIFY_PATH" ]] || die "The user deployment is not writable; Spicetify cannot patch it without sudo."

ok "Known-good Spotify app is deployed in Goinfre and its app directory is writable."
printf '\nNext steps:\n'
printf '  1. Close every Spotify instance.\n'
printf '  2. Run: ./launch.sh\n'
printf '  3. Confirm login, playback, and rendering.\n'
printf '  4. Only after those tests pass, run: ./scripts/configure.sh\n'
printf '\nThe system Spotify installation remains untouched.\n'
