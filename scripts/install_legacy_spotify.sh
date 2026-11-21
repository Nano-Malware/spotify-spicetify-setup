#!/usr/bin/env bash
# Install the historical Spotify 1.2.52 build and its matching 24.08 stack.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths

require_command flatpak
require_command curl
require_command sha256sum
require_command awk
require_command grep
require_command tar

TARGET_VERSION="1.2.52.442.g01893f92"
TARGET_RUNTIME="org.freedesktop.Platform/x86_64/24.08"
TARGET_REF="app/com.spotify.Client/x86_64/stable"
RUNTIME_REF="org.freedesktop.Platform//24.08"
MESA_REF="org.freedesktop.Platform.GL.default//24.08"
RELEASE_TAG="spotify-1.2.52.442"
REPO_ARCHIVE_NAME="spotify-1.2.52.442-repo.tar.gz"
CHECKSUM_NAME="$REPO_ARCHIVE_NAME.sha256"
REMOTE_NAME="spotify-legacy"
LOCAL_REPO_DIR="$SETUP_DIR/spotify-flatpak-repo"
RELEASE_URL="https://github.com/Nano-Malware/spotify-spicetify-setup/releases/download/$RELEASE_TAG"

current_version="$(spotify_installed_version || true)"
current_runtime="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null || true)"
current_ref="$(flatpak info --user --show-ref "$APP_ID" 2>/dev/null || true)"

if [[ "$current_version" == "$TARGET_VERSION" && "$current_runtime" == "$TARGET_RUNTIME" && "$current_ref" == "$TARGET_REF" ]]; then
    info "The requested Spotify build is already installed: $TARGET_VERSION"
else
    if flatpak ps --columns=application 2>/dev/null | grep -Fxq "$APP_ID"; then
        die "Spotify is running. Close both system and Goinfre Spotify before replacing the user installation."
    fi
    warn "Freedesktop 24.08 reached end of life in September 2026 and no longer receives normal security updates. This is an intentional compatibility pin."
fi

if ! flatpak remotes --user --columns=name | grep -Fxq flathub; then
    info "Adding Flathub to the Goinfre user installation."
    flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL"
fi

# The Flathub 24.08 branch now points to Mesa 26.1.x, which is too new
# for this machine's AMD DRM 3.42. Export the exact known-good 25.2.6
# commits from the existing system installation as local Flatpak bundles.
MESA_EXTRA_REF="org.freedesktop.Platform.GL.default//24.08extra"
MESA_VERSION="25.2.6"
MESA_COMMIT="e7cca7bcddd35029a6cb5720367f49255a6be3d338eaf1e7a57945cbe84e03ec"
MESA_EXTRA_COMMIT="765326f0e2abc4b69240f4283bb2437b04d468ce2377cf716d05b3d71a8e646e"
TMP_DIR="$(mktemp -d "$SETUP_DIR/.spotify-legacy.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

info "Ensuring Freedesktop 24.08 is installed in Goinfre."
if ! flatpak info --user "$RUNTIME_REF" >/dev/null 2>&1; then
    flatpak install --user --noninteractive --assumeyes flathub "$RUNTIME_REF"
fi

project_mesa_commit="$(flatpak info --user --show-commit "$MESA_REF" 2>/dev/null || true)"
project_mesa_extra_commit="$(flatpak info --user --show-commit "$MESA_EXTRA_REF" 2>/dev/null || true)"

if [[ "$project_mesa_commit" == "$MESA_COMMIT" && "$project_mesa_extra_commit" == "$MESA_EXTRA_COMMIT" ]]; then
    info "The project-owned installation already has the pinned Mesa $MESA_VERSION pair."
else
    system_mesa_version="$(flatpak --system info "$MESA_REF" 2>/dev/null |
        awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || true)"
    system_mesa_extra_version="$(flatpak --system info "$MESA_EXTRA_REF" 2>/dev/null |
        awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}' || true)"
    system_mesa_commit="$(flatpak --system info --show-commit "$MESA_REF" 2>/dev/null || true)"
    system_mesa_extra_commit="$(flatpak --system info --show-commit "$MESA_EXTRA_REF" 2>/dev/null || true)"

    if [[ "$system_mesa_version" != "$MESA_VERSION" ||
          "$system_mesa_extra_version" != "$MESA_VERSION" ||
          "$system_mesa_commit" != "$MESA_COMMIT" ||
          "$system_mesa_extra_commit" != "$MESA_EXTRA_COMMIT" ]]; then
        die "The exact compatible Mesa $MESA_VERSION pair is not installed in the system Flatpak installation. Refusing to use Flathub's newer Mesa branch. System versions: \${system_mesa_version:-missing}/\${system_mesa_extra_version:-missing}."
    fi

    system_mesa_location="$(flatpak --system info --show-location "$MESA_REF" 2>/dev/null || true)"
    [[ -n "$system_mesa_location" ]] ||
        die "Could not locate the system Mesa installation to export its verified commits."
    system_install_root="\${system_mesa_location%%/runtime/*}"
    system_repo="$system_install_root/repo"
    [[ -f "$system_repo/config" && -d "$system_repo/objects" ]] ||
        die "The system Flatpak OSTree repository is not readable at $system_repo."

    mesa_bundle="$TMP_DIR/mesa-24.08.flatpak"
    mesa_extra_bundle="$TMP_DIR/mesa-24.08extra.flatpak"

    info "Exporting the verified system Mesa $MESA_VERSION commits as local Flatpak bundles."
    flatpak build-bundle --runtime --from-commit="$MESA_COMMIT" \
        "$system_repo" "$mesa_bundle" org.freedesktop.Platform.GL.default 24.08
    flatpak build-bundle --runtime --from-commit="$MESA_EXTRA_COMMIT" \
        "$system_repo" "$mesa_extra_bundle" org.freedesktop.Platform.GL.default 24.08extra

    [[ -s "$mesa_bundle" && -s "$mesa_extra_bundle" ]] ||
        die "Could not create both verified Mesa runtime bundles."

    flatpak mask --user --remove "$MESA_REF" >/dev/null 2>&1 || true
    flatpak mask --user --remove "$MESA_EXTRA_REF" >/dev/null 2>&1 || true

    if flatpak info --user "$MESA_REF" >/dev/null 2>&1; then
        info "Replacing the newer Goinfre Mesa GL extension with the verified 25.2.6 bundle."
        flatpak uninstall --user --noninteractive --assumeyes "$MESA_REF"
    fi
    if flatpak info --user "$MESA_EXTRA_REF" >/dev/null 2>&1; then
        info "Replacing the newer Goinfre Mesa GL-extra extension with the verified 25.2.6 bundle."
        flatpak uninstall --user --noninteractive --assumeyes "$MESA_EXTRA_REF"
    fi

    info "Installing the verified Mesa 25.2.6 GL bundle in Goinfre."
    flatpak install --user --noninteractive --assumeyes --bundle "$mesa_bundle"
    info "Installing the verified Mesa 25.2.6 GL-extra bundle in Goinfre."
    flatpak install --user --noninteractive --assumeyes --bundle "$mesa_extra_bundle"
fi

mesa_version="$(flatpak info --user "$MESA_REF" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}')"
mesa_extra_version="$(flatpak info --user "$MESA_EXTRA_REF" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}')"
mesa_commit="$(flatpak info --user --show-commit "$MESA_REF" 2>/dev/null || true)"
mesa_extra_commit="$(flatpak info --user --show-commit "$MESA_EXTRA_REF" 2>/dev/null || true)"

[[ "$mesa_version" == "$MESA_VERSION" && "$mesa_extra_version" == "$MESA_VERSION" ]] ||
    die "Mesa version verification failed. Expected $MESA_VERSION for both 24.08 GL extensions; found \${mesa_version:-missing}/\${mesa_extra_version:-missing}."
[[ "$mesa_commit" == "$MESA_COMMIT" && "$mesa_extra_commit" == "$MESA_EXTRA_COMMIT" ]] ||
    die "Mesa commit verification failed. The pinned 25.2.6 commits are not active."

info "Verified Goinfre Mesa $mesa_version / $mesa_extra_version and both exact commits."
if [[ "$current_version" != "$TARGET_VERSION" || "$current_runtime" != "$TARGET_RUNTIME" || "$current_ref" != "$TARGET_REF" ]]; then
    info "Downloading the verified Spotify $TARGET_VERSION repository archive..."
    if ! curl -fL --retry 3 --retry-delay 2 "$RELEASE_URL/$REPO_ARCHIVE_NAME" -o "$TMP_DIR/$REPO_ARCHIVE_NAME"; then
        die "The Spotify $TARGET_VERSION repository archive is not available yet. Check the GitHub Actions build workflow: https://github.com/Nano-Malware/spotify-spicetify-setup/actions"
    fi
    if ! curl -fL --retry 3 --retry-delay 2 "$RELEASE_URL/$CHECKSUM_NAME" -o "$TMP_DIR/$CHECKSUM_NAME"; then
        die "The Spotify repository archive checksum is not available. Check the GitHub Actions build workflow."
    fi

    (
        cd "$TMP_DIR"
        sha256sum --check "$CHECKSUM_NAME"
    )

    if ! tar -tzf "$TMP_DIR/$REPO_ARCHIVE_NAME" | awk '
        $0 !~ /^spotify-flatpak-repo(\/|$)/ || $0 ~ /^\// || $0 ~ /(^|\/)\.\.(\/|$)/ { bad = 1 }
        END { exit bad }
    '; then
        die "The repository archive contains an unexpected or unsafe path."
    fi

    mkdir -p "$TMP_DIR/extracted"
    tar --no-same-owner --no-same-permissions -xzf "$TMP_DIR/$REPO_ARCHIVE_NAME" -C "$TMP_DIR/extracted"
    STAGED_REPO="$TMP_DIR/extracted/spotify-flatpak-repo"
    [[ -f "$STAGED_REPO/config" && -s "$STAGED_REPO/summary" && -d "$STAGED_REPO/objects" ]] ||
        die "The downloaded archive does not contain a complete Flatpak repository."

    rm -rf -- "$LOCAL_REPO_DIR"
    mv -- "$STAGED_REPO" "$LOCAL_REPO_DIR"
    REPO_URL="file://$LOCAL_REPO_DIR"

    if flatpak remotes --user --columns=name | grep -Fxq "$REMOTE_NAME"; then
        flatpak remote-modify --user --no-gpg-verify --url="$REPO_URL" "$REMOTE_NAME"
    else
        flatpak remote-add --user --no-gpg-verify "$REMOTE_NAME" "$REPO_URL"
    fi

    if ! REMOTE_REF="$(flatpak remote-info --user --show-ref "$REMOTE_NAME" "$APP_ID//stable")"; then
        die "The local Spotify repository does not expose the expected stable application ref."
    fi
    [[ "$REMOTE_REF" == "app/com.spotify.Client/x86_64/stable" ]] ||
        die "Unexpected application ref in the local Spotify repository: $REMOTE_REF"

    if ! REMOTE_METADATA="$(flatpak remote-info --user --show-metadata "$REMOTE_NAME" "$APP_ID//stable")"; then
        die "Could not read Spotify's Flatpak metadata from the local repository."
    fi
    printf '%s\n' "$REMOTE_METADATA" | grep -Fq '[Extra Data]' ||
        die "Spotify's extra-data metadata is missing from the local Flatpak repository."

    flatpak mask --user --remove "$APP_ID" >/dev/null 2>&1 || true
    if flatpak info --user "$APP_ID" >/dev/null 2>&1; then
        info "Replacing the existing project-owned Spotify app. Your profile and login data are kept."
        flatpak uninstall --user --noninteractive --assumeyes "$APP_ID"
    fi

    info "Installing Spotify $TARGET_VERSION from the verified local Flatpak repository..."
    flatpak install --user --noninteractive --assumeyes "$REMOTE_NAME" "$APP_ID//stable"

    installed_origin="$(flatpak info --user --show-origin "$APP_ID")"
    [[ "$installed_origin" == "$REMOTE_NAME" ]] ||
        die "Spotify was installed from unexpected origin '$installed_origin', not '$REMOTE_NAME'."
fi

installed_version="$(spotify_installed_version || true)"
installed_runtime="$(flatpak info --user --show-runtime "$APP_ID" 2>/dev/null || true)"
installed_ref="$(flatpak info --user --show-ref "$APP_ID" 2>/dev/null || true)"
printf '\nInstalled Spotify version: %s\n' "${installed_version:-unknown}"
printf 'Installed runtime: %s\n' "${installed_runtime:-unknown}"
printf 'Installed ref: %s\n' "${installed_ref:-unknown}"
printf 'Goinfre Mesa: %s\n' "$mesa_version"

[[ "$installed_version" == "$TARGET_VERSION" ]] ||
    die "Spotify version verification failed; expected $TARGET_VERSION."
[[ "$installed_runtime" == "$TARGET_RUNTIME" ]] ||
    die "Spotify runtime verification failed; expected $TARGET_RUNTIME."
[[ "$installed_ref" == "$TARGET_REF" ]] ||
    die "Spotify ref verification failed; expected $TARGET_REF."

# Keep this historical version pinned in the project-owned user installation.
flatpak mask --user "$APP_ID"
flatpak mask --user "$MESA_REF"
if flatpak info --user "$MESA_EXTRA_REF" >/dev/null 2>&1; then
    flatpak mask --user "$MESA_EXTRA_REF"
fi
ok "Spotify $TARGET_VERSION and its compatible 24.08 Mesa stack are installed and pinned in Goinfre."
