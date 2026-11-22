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

installed_version="$(spotify_installed_version || true)"
[[ "$installed_version" == "$TARGET_SPOTIFY_VERSION" ]] ||
    die "Spicetify setup expected Spotify $TARGET_SPOTIFY_VERSION, found ${installed_version:-unknown}."

SPOTIFY_PATH="$(spotify_install_path)" ||
    die "Could not determine the project-owned Spotify installation path."
[[ -d "$SPOTIFY_PATH/Apps" ]] ||
    die "Spotify's Apps directory is missing: $SPOTIFY_PATH/Apps"
[[ -w "$SPOTIFY_PATH" && -w "$SPOTIFY_PATH/Apps" ]] ||
    die "Spotify's Goinfre application files are not writable by this user."
[[ -d "$(dirname -- "$PREFS_PATH")" ]] ||
    mkdir -p "$(dirname -- "$PREFS_PATH")"

# Always use the project-owned Flatpak path and the real per-user Spotify prefs.
"$SPICETIFY_BIN" config spotify_path "$SPOTIFY_PATH" >/dev/null
"$SPICETIFY_BIN" config prefs_path "$PREFS_PATH" >/dev/null
# Avoid a separate GitHub API release check on every launcher run.
"$SPICETIFY_BIN" config check_spicetify_update 0 >/dev/null

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

# Install Marketplace only when its application files are absent. Do not
# overwrite an existing Marketplace directory or any other user's themes/apps.
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

# Preserve any other custom apps and any user-selected theme.
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
        "$SPICETIFY_BIN" config custom_apps "$current_apps" >/dev/null
        ;;
esac

current_theme="$(ini_value Setting current_theme)"
if [[ -z "$current_theme" ]]; then
    "$SPICETIFY_BIN" config current_theme marketplace >/dev/null
fi
"$SPICETIFY_BIN" config inject_css 1 >/dev/null
"$SPICETIFY_BIN" config replace_colors 1 >/dev/null

# A first launch is needed for Spotify to create its preferences file. Do not
# attempt a backup/apply until the user has opened Spotify and logged in.
if [[ ! -s "$PREFS_PATH" ]]; then
    warn "Spotify preferences do not exist yet. Spotify will launch unmodified once; sign in, leave it open for at least 60 seconds, close it, then run ./launch.sh again."
    exit 0
fi
[[ -r "$PREFS_PATH" && -w "$PREFS_PATH" ]] ||
    die "Spotify preferences are not readable and writable: $PREFS_PATH"

cli_version="$("$SPICETIFY_BIN" --version | tail -n 1 | tr -d '\r')"
config_hash="$(sha256sum "$SPICETIFY_CONFIG_FILE" | awk '{print $1}')"
APPLIED_MARKER="$SETUP_DIR/.spicetify-applied"

# Skip patching when the target Spotify version, Spicetify version, and config
# are unchanged. This makes repeated launches quick and avoids rebaking backups.
if [[ -f "$APPLIED_MARKER" &&
      "$(sed -n '1p' "$APPLIED_MARKER")" == "$installed_version" &&
      "$(sed -n '2p' "$APPLIED_MARKER")" == "$cli_version" &&
      "$(sed -n '3p' "$APPLIED_MARKER")" == "$config_hash" ]]; then
    ok "Spicetify is already applied to Spotify $installed_version."
    exit 0
fi

# Never rewrite the Spotify app files while a Spotify instance is running.
if flatpak ps --columns=application 2>/dev/null | grep -Fxq "$APP_ID"; then
    die "Spotify is currently running. Close every Spotify window completely, then run ./launch.sh again to apply Spicetify safely."
fi

backup_version="$(ini_value Backup version)"
backup_cli_version="$(ini_value Backup with)"
backup_dir="$SPICETIFY_STATE/Backup"
backup_exists=0
if [[ -d "$backup_dir" ]] && find "$backup_dir" -mindepth 1 -print -quit | grep -q .; then
    backup_exists=1
fi

if [[ "$backup_exists" == "1" &&
      "$backup_version" == "$installed_version" &&
      "$backup_cli_version" == "$cli_version" ]]; then
    info "A matching vanilla Spotify backup already exists; applying the configured Marketplace setup."
    run_with_progress "Applying Spicetify to Spotify" \
        "$SPICETIFY_BIN" apply --no-restart ||
        die "Spicetify apply failed. Review the messages above before retrying."
else
    info "Creating or refreshing the vanilla Spotify backup, then applying Spicetify."
    run_with_progress "Backing up and applying Spicetify" \
        "$SPICETIFY_BIN" backup apply --no-restart ||
        die "Spicetify backup/apply failed. If an old backup is reported as non-vanilla, restore or reinstall the pinned Spotify build before retrying."
fi

backup_version="$(ini_value Backup version)"
backup_cli_version="$(ini_value Backup with)"
[[ "$backup_version" == "$installed_version" && "$backup_cli_version" == "$cli_version" ]] ||
    die "Spicetify did not record a backup for Spotify $installed_version with CLI $cli_version."

config_hash="$(sha256sum "$SPICETIFY_CONFIG_FILE" | awk '{print $1}')"
printf '%s\n%s\n%s\n' "$installed_version" "$cli_version" "$config_hash" > "$APPLIED_MARKER.tmp"
mv -- "$APPLIED_MARKER.tmp" "$APPLIED_MARKER"
ok "Spicetify and Marketplace are applied to Spotify $installed_version."
