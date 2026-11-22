#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

PROJECT_DIR="$TMP_ROOT/project"
SETUP_DIR="$TMP_ROOT/setup"
HOME_DIR="$TMP_ROOT/home"
SIM_STATE="$TMP_ROOT/state"
SIM_APP_LOCATION="$TMP_ROOT/flatpak/app/com.spotify.Client/x86_64/stable/active"
mkdir -p "$PROJECT_DIR/scripts" "$SETUP_DIR/bin" \
    "$SETUP_DIR/spotify-flatpak-repo/objects" "$SETUP_DIR/xdg-config/spicetify/CustomApps/marketplace" \
    "$SETUP_DIR/xdg-config/spicetify/Themes/marketplace" "$HOME_DIR/.var/app/com.spotify.Client/config/spotify" \
    "$SIM_STATE" "$TMP_ROOT/bin"
cp "$ROOT_DIR/scripts/common.sh" "$PROJECT_DIR/scripts/common.sh"
cp "$ROOT_DIR/scripts/install_legacy_spotify.sh" "$PROJECT_DIR/scripts/install_legacy_spotify.sh"
cp "$ROOT_DIR/scripts/configure_spicetify.sh" "$PROJECT_DIR/scripts/configure_spicetify.sh"
printf '%s\n' "$SETUP_DIR" > "$PROJECT_DIR/.setup-dir"
printf '%s\n' 'repo-config' > "$SETUP_DIR/spotify-flatpak-repo/config"
printf '%s\n' 'repo-summary' > "$SETUP_DIR/spotify-flatpak-repo/summary"
printf '%s\n' \
    'e7cca7bcddd35029a6cb5720367f49255a6be3d338eaf1e7a57945cbe84e03ec' \
    '765326f0e2abc4b69240f4283bb2437b04d468ce2377cf716d05b3d71a8e646e' \
    'simulated-gl-commit' \
    'simulated-extra-commit' > "$SETUP_DIR/.mesa-24.08-pinned"
printf '%s\n' '[Setting]' 'current_theme = marketplace' '' '[AdditionalOptions]' 'custom_apps = marketplace' > "$SETUP_DIR/xdg-config/spicetify/config-xpui.ini"
printf '%s\n' '{"name":"marketplace"}' > "$SETUP_DIR/xdg-config/spicetify/CustomApps/marketplace/manifest.json"
printf '%s\n' 'export default function render() {}' > "$SETUP_DIR/xdg-config/spicetify/CustomApps/marketplace/index.js"
printf '%s\n' '[Base]' 'main = 1' > "$SETUP_DIR/xdg-config/spicetify/Themes/marketplace/color.ini"
printf '%s\n' 'app.last-launched-version="1.2.52.442.g01893f92"' > "$HOME_DIR/.var/app/com.spotify.Client/config/spotify/prefs"
mkdir -p "$SIM_APP_LOCATION/files/extra/share/spotify/Apps/xpui"
printf '%s\n' 'old incomplete patch' > "$SIM_APP_LOCATION/files/extra/share/spotify/Apps/xpui/spicetify-routes-marketplace.js"
touch "$SETUP_DIR/bin/spicetify"
chmod +x "$SETUP_DIR/bin/spicetify"
touch "$SIM_STATE/app-installed"

cat > "$TMP_ROOT/bin/flatpak" <<'FLATPAK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$SIM_STATE/flatpak.log"
command_name="$1"
shift

has_arg() {
    local wanted="$1"
    shift
    local value
    for value in "$@"; do
        [[ "$value" == "$wanted" ]] && return 0
    done
    return 1
}

case "$command_name" in
    remotes)
        printf 'flathub\n'
        [[ ! -f "$SIM_STATE/remote-url" ]] || printf 'spotify-legacy\n'
        ;;
    remote-add|remote-modify)
        remote_name=""
        remote_url=""
        for value in "$@"; do
            [[ "$value" == "spotify-legacy" ]] && remote_name="$value"
            [[ "$value" == file://* ]] && remote_url="$value"
        done
        [[ "$remote_name" == "spotify-legacy" && "$remote_url" == file://* ]]
        printf '%s\n' "$remote_url" > "$SIM_STATE/remote-url"
        ;;
    remote-info)
        [[ -s "$SIM_STATE/remote-url" ]] || exit 1
        if has_arg --show-ref "$@"; then
            printf 'app/com.spotify.Client/x86_64/stable\n'
        else
            printf '[Application]\nname=Spotify\n\n[Extra Data]\nname=spotify.deb\n'
        fi
        ;;
    info)
        mode=""
        target=""
        for value in "$@"; do
            case "$value" in
                --show-runtime) mode="runtime" ;;
                --show-ref) mode="ref" ;;
                --show-location) mode="location" ;;
                --show-origin) mode="origin" ;;
                --show-commit) mode="commit" ;;
                --user|--system) ;;
                *) target="$value" ;;
            esac
        done
        case "$target" in
            com.spotify.Client)
                [[ -f "$SIM_STATE/app-installed" ]] || exit 1
                case "$mode" in
                    runtime) printf 'org.freedesktop.Platform/x86_64/24.08\n' ;;
                    ref) printf 'app/com.spotify.Client/x86_64/stable\n' ;;
                    location) printf '%s\n' "$SIM_APP_LOCATION" ;;
                    origin) printf 'spotify-legacy\n' ;;
                    *) printf 'Name: Spotify\nVersion: 1.2.52.442.g01893f92\n' ;;
                esac
                ;;
            org.freedesktop.Platform.GL.default//24.08|org.freedesktop.Platform.GL.default//24.08extra)
                if [[ "$mode" == "commit" ]]; then
                    if [[ "$target" == *24.08extra ]]; then
                        printf 'simulated-extra-commit\n'
                    else
                        printf 'simulated-gl-commit\n'
                    fi
                else
                    printf 'Name: Mesa\nVersion: 25.2.6\n'
                fi
                ;;
            *) printf 'unexpected info target: %s\n' "$target" >&2; exit 2 ;;
        esac
        ;;
    ps)
        exit 0
        ;;
    mask)
        exit 0
        ;;
    uninstall)
        has_arg com.spotify.Client "$@" || exit 2
        rm -f "$SIM_STATE/app-installed"
        rm -rf "$SIM_APP_LOCATION"
        ;;
    install)
        has_arg com.spotify.Client//stable "$@" || exit 2
        [[ -s "$SIM_STATE/remote-url" ]] || exit 1
        touch "$SIM_STATE/app-installed"
        mkdir -p "$SIM_APP_LOCATION/files/extra/share/spotify/Apps"
        touch "$SIM_APP_LOCATION/files/extra/share/spotify/Apps/xpui.spa"
        touch "$SIM_APP_LOCATION/files/extra/share/spotify/Apps/login.spa"
        ;;
    *)
        printf 'unsupported simulated flatpak operation: %s %s\n' "$command_name" "$*" >&2
        exit 2
        ;;
esac
FLATPAK
chmod +x "$TMP_ROOT/bin/flatpak"

cat > "$SETUP_DIR/bin/spicetify" <<'SPICETIFY'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$SIM_STATE/spicetify.log"
case "$1" in
    config)
        exit 0
        ;;
    --version)
        printf 'v2.46.7\n'
        ;;
    apply)
        if [[ ! -e "$SIM_STATE/apply-failed" ]]; then
            touch "$SIM_STATE/apply-failed"
            printf "error  You haven't backed up and Spotify cannot be backed up at this state. Please re-install Spotify then run \"spicetify backup apply\"\n" >&2
            exit 1
        fi
        printf 'unexpected second apply call\n' >&2
        exit 1
        ;;
    backup)
        [[ "${2:-}" == "apply" ]] || exit 2
        mkdir -p "$SIM_APP_LOCATION/files/extra/share/spotify/Apps/xpui"
        printf '%s\n' 'simulated successfully patched Marketplace route' \
            > "$SIM_APP_LOCATION/files/extra/share/spotify/Apps/xpui/spicetify-routes-marketplace.js"
        printf 'simulated native backup and apply succeeded\n'
        ;;
    *)
        printf 'unsupported simulated Spicetify operation: %s\n' "$*" >&2
        exit 2
        ;;
esac
SPICETIFY
chmod +x "$SETUP_DIR/bin/spicetify"

export HOME="$HOME_DIR"
export SIM_STATE SIM_APP_LOCATION
export SPOTIFY_SETUP_DIR="$SETUP_DIR"
export PATH="$TMP_ROOT/bin:$PATH"

printf '%s\n' '[SIM] 1. Existing pinned Spotify with missing spotify-legacy remote.'
bash "$PROJECT_DIR/scripts/install_legacy_spotify.sh" > "$TMP_ROOT/install.log" 2>&1
[[ -s "$SIM_STATE/remote-url" ]] || {
    cat "$TMP_ROOT/install.log"
    printf '%s\n' '[FAIL] Installer did not register the missing local Flatpak remote.' >&2
    exit 1
}
grep -Fq 'Registering the project-owned Spotify repository' "$TMP_ROOT/install.log"

printf '%s\n' '[SIM] 2. Remove remote again and simulate a broken Spicetify apply.'
rm -f "$SIM_STATE/remote-url"
bash "$PROJECT_DIR/scripts/configure_spicetify.sh" > "$TMP_ROOT/configure.log" 2>&1 || {
    cat "$TMP_ROOT/configure.log"
    printf '%s\n' '[FAIL] Spicetify recovery workflow failed.' >&2
    exit 1
}

[[ -s "$SIM_STATE/remote-url" ]]
[[ -f "$SIM_STATE/app-installed" ]]
[[ -s "$SIM_APP_LOCATION/files/extra/share/spotify/Apps/xpui/spicetify-routes-marketplace.js" ]]
[[ -s "$SETUP_DIR/.spicetify-applied" ]]
[[ -s "$HOME/.var/app/com.spotify.Client/config/spotify/prefs" ]]
grep -Fq 'Removing damaged pinned Spotify app' "$TMP_ROOT/configure.log"
grep -Fq 'Applying Spicetify to clean Spotify' "$TMP_ROOT/configure.log"
grep -Fq 'simulated native backup and apply succeeded' "$TMP_ROOT/configure.log"

if grep -Fq -- '--system' "$SIM_STATE/flatpak.log"; then
    printf '%s\n' '[FAIL] A simulated Flatpak command targeted the system installation.' >&2
    exit 1
fi

printf '%s\n' '[PASS] Missing remote was recreated, damaged Goinfre Spotify was reinstalled, native Spicetify apply completed, and the profile remained intact.'
printf '%s\n' '[PASS] System-wide Flatpak installation was never targeted.'
