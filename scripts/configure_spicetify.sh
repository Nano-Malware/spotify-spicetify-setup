#!/usr/bin/env bash
# Configure and apply Spicetify to the project-owned Spotify installation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths

require_spicetify
ensure_user_spotify_installed
require_command curl
require_command sha256sum
require_command awk
require_command grep

spicetify_cmd() {
    env -u SPICETIFY_STATE \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" \
        SPICETIFY_CONFIG="$SPICETIFY_CONFIG_DIR" \
        "$SPICETIFY_BIN" "$@"
}

installed_version="$(spotify_installed_version || true)"
[[ "$installed_version" == "$TARGET_SPOTIFY_VERSION" ]] ||
    die "Spicetify setup expected Spotify $TARGET_SPOTIFY_VERSION, found ${installed_version:-unknown}."

SPOTIFY_PATH="$(spotify_install_path)" ||
    die "Could not determine the project-owned Spotify installation path."
[[ -d "$SPOTIFY_PATH/Apps" ]] ||
    die "Spotify's Apps directory is missing: $SPOTIFY_PATH/Apps"
[[ -w "$SPOTIFY_PATH" && -w "$SPOTIFY_PATH/Apps" ]] ||
    die "Spotify's Goinfre application files are not writable by this user."
mkdir -p "$(dirname -- "$PREFS_PATH")"

spicetify_cmd config spotify_path "$SPOTIFY_PATH" >/dev/null
spicetify_cmd config prefs_path "$PREFS_PATH" >/dev/null
spicetify_cmd config check_spicetify_update 0 >/dev/null

ini_value() {
    local section="$1"
    local key="$2"

    awk -v wanted_section="$section" -v wanted_key="$key" '
        /^\[/ {
            active = ($0 == "[" wanted_section "]")
            next
        }
        active {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line == "" || line ~ /^[;#]/)
                next
            split(line, pair, "=")
            name = pair[1]
            gsub(/[[:space:]]/, "", name)
            if (name == wanted_key) {
                value = substr(line, index(line, "=") + 1)
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                print value
                exit
            }
        }
    ' "$SPICETIFY_CONFIG_FILE"
}

MARKETPLACE_APP_DIR="$SPICETIFY_CONFIG_DIR/CustomApps/marketplace"
MARKETPLACE_THEME_DIR="$SPICETIFY_CONFIG_DIR/Themes/marketplace"
MARKETPLACE_ZIP_URL="https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip"
MARKETPLACE_COLOR_URL="https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini"

if [[ ! -s "$MARKETPLACE_APP_DIR/manifest.json" || ! -s "$MARKETPLACE_APP_DIR/index.js" ]]; then
    [[ ! -e "$MARKETPLACE_APP_DIR" ]] ||
        die "Marketplace exists but is incomplete at $MARKETPLACE_APP_DIR. Refusing to overwrite it."
    require_command unzip
    marketplace_tmp="$(mktemp -d "$SETUP_DIR/.marketplace.XXXXXX")"
    trap 'rm -rf -- "$marketplace_tmp"' EXIT
    mkdir -p "$marketplace_tmp/unpacked" "$SPICETIFY_CONFIG_DIR/CustomApps"
    info "Marketplace is missing; downloading its official release."
    run_with_progress "Downloading Spicetify Marketplace" \
        curl --fail --location --retry 3 --retry-delay 2 --silent --show-error \
        "$MARKETPLACE_ZIP_URL" -o "$marketplace_tmp/marketplace.zip"
    run_with_progress "Extracting Spicetify Marketplace" \
        unzip -q -o "$marketplace_tmp/marketplace.zip" -d "$marketplace_tmp/unpacked"
    [[ -s "$marketplace_tmp/unpacked/marketplace-dist/manifest.json" &&
       -s "$marketplace_tmp/unpacked/marketplace-dist/index.js" ]] ||
        die "The Marketplace archive did not contain the expected application files."
    mv -- "$marketplace_tmp/unpacked/marketplace-dist" "$MARKETPLACE_APP_DIR"
    rm -rf -- "$marketplace_tmp"
    trap - EXIT
    ok "Spicetify Marketplace installed."
else
    info "Spicetify Marketplace is already installed."
fi

mkdir -p "$MARKETPLACE_THEME_DIR"
if [[ ! -s "$MARKETPLACE_THEME_DIR/color.ini" ]]; then
    info "Installing the Marketplace placeholder theme."
    run_with_progress "Downloading Marketplace theme settings" \
        curl --fail --location --retry 3 --retry-delay 2 --silent --show-error \
        "$MARKETPLACE_COLOR_URL" -o "$MARKETPLACE_THEME_DIR/color.ini"
fi

current_apps="$(ini_value AdditionalOptions custom_apps)"
apps_compact="${current_apps//[[:space:]]/}"
case "|$apps_compact|" in
    *"|marketplace|"*) ;;
    *)
        if [[ -n "$current_apps" ]]; then
            current_apps="$current_apps|marketplace"
        else
            current_apps="marketplace"
        fi
        spicetify_cmd config custom_apps "$current_apps" >/dev/null
        ;;
esac

current_theme="$(ini_value Setting current_theme)"
if [[ -z "$current_theme" ]]; then
    spicetify_cmd config current_theme marketplace >/dev/null
fi
spicetify_cmd config inject_css 1 >/dev/null
spicetify_cmd config replace_colors 1 >/dev/null

if [[ ! -s "$PREFS_PATH" ]]; then
    warn "Spotify has not created its preferences yet. The launcher must open Spotify once, then it will finish Spicetify setup after you close Spotify."
    exit 10
fi
[[ -r "$PREFS_PATH" && -w "$PREFS_PATH" ]] ||
    die "Spotify preferences are not readable and writable: $PREFS_PATH"

prefs_version="$(awk -F= '$1 == "app.last-launched-version" {
    value = $2
    gsub(/^[[:space:]]*"/, "", value)
    gsub(/"[[:space:]]*$/, "", value)
    print value
    exit
}' "$PREFS_PATH")"
if [[ "$prefs_version" != "$installed_version" ]]; then
    warn "Spotify preferences record ${prefs_version:-no version}, but the pinned app is $installed_version. The launcher must open the pinned Spotify once, then finish Spicetify setup after you close it."
    exit 10
fi

cli_version="$(spicetify_cmd --version | tail -n 1 | tr -d '\r')"
config_hash="$(sha256sum "$SPICETIFY_CONFIG_FILE" | awk '{print $1}')"
APPLIED_MARKER="$SETUP_DIR/.spicetify-applied"

apps_dir="$SPOTIFY_PATH/Apps"
marketplace_entry="$apps_dir/xpui/spicetify-routes-marketplace.js"
spotify_is_patched=0
if [[ -s "$marketplace_entry" ]]; then
    spotify_is_patched=1
fi

if [[ "$spotify_is_patched" == "1" &&
      -f "$APPLIED_MARKER" &&
      "$(sed -n '1p' "$APPLIED_MARKER")" == "$installed_version" &&
      "$(sed -n '2p' "$APPLIED_MARKER")" == "$cli_version" &&
      "$(sed -n '3p' "$APPLIED_MARKER")" == "$config_hash" ]]; then
    ok "Spicetify and Marketplace are already applied to Spotify $installed_version; skipping patching."
    exit 0
fi

if flatpak ps --columns=application 2>/dev/null | grep -Fxq "$APP_ID"; then
    die "Spotify is currently running. Close every Spotify window completely, then run ./launch.sh again to apply Spicetify safely."
fi

if [[ "$spotify_is_patched" == "1" ]]; then
    info "Updating the existing Spicetify patch."
    run_with_progress "Applying Spicetify" \
        spicetify_cmd apply --no-restart ||
        die "Spicetify apply failed."
else
    info "First Spicetify setup: using Spicetify's built-in backup/apply command."
    run_with_progress "Applying Spicetify for the first time" \
        spicetify_cmd backup apply --no-restart ||
        die "Spicetify's first-time backup/apply command failed. The repository does not manage backup files; check the Spicetify error above."
fi

[[ -s "$marketplace_entry" ]] ||
    die "Spicetify finished without creating the Marketplace route. The patch was not marked as complete."

config_hash="$(sha256sum "$SPICETIFY_CONFIG_FILE" | awk '{print $1}')"
printf '%s\n%s\n%s\n' "$installed_version" "$cli_version" "$config_hash" > "$APPLIED_MARKER.tmp"
mv -- "$APPLIED_MARKER.tmp" "$APPLIED_MARKER"
ok "Spicetify and Marketplace are applied to Spotify $installed_version."
