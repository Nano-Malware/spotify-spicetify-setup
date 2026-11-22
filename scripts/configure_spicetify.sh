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

# Keep Spicetify's named state folders separate. SPICETIFY_STATE overrides
# the entire state path and makes Backup and Extracted collide in CLI v2.46.7.
SPICETIFY_STATE_DIR="$XDG_STATE_HOME/spicetify"
backup_dir="$SPICETIFY_STATE_DIR/Backup"
adopt_backup_dir="$backup_dir"

# Force every CLI call to use project-owned XDG/config paths and ignore any
# SPICETIFY_STATE value inherited from the user's shell.
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
[[ -d "$(dirname -- "$PREFS_PATH")" ]] ||
    mkdir -p "$(dirname -- "$PREFS_PATH")"

# Always use the project-owned Flatpak path and the real per-user Spotify prefs.
spicetify_cmd config spotify_path "$SPOTIFY_PATH" >/dev/null
spicetify_cmd config prefs_path "$PREFS_PATH" >/dev/null
# Avoid a separate GitHub API release check on every launcher run.
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
        spicetify_cmd config custom_apps "$current_apps" >/dev/null
        ;;
esac

current_theme="$(ini_value Setting current_theme)"
if [[ -z "$current_theme" ]]; then
    spicetify_cmd config current_theme marketplace >/dev/null
fi
spicetify_cmd config inject_css 1 >/dev/null
spicetify_cmd config replace_colors 1 >/dev/null

# A first launch is needed for Spotify to create its preferences file. Do not
# attempt a backup/apply until the user has opened Spotify and logged in.
if [[ ! -s "$PREFS_PATH" ]]; then
    warn "Spotify preferences do not exist yet. Spotify will launch unmodified once; sign in, leave it open for at least 60 seconds, close it, then run ./launch.sh again."
    exit 0
fi
[[ -r "$PREFS_PATH" && -w "$PREFS_PATH" ]] ||
    die "Spotify preferences are not readable and writable: $PREFS_PATH"

cli_version="$(spicetify_cmd --version | tail -n 1 | tr -d '\r')"

# Migrate backups created by the previous project layout, which set
# SPICETIFY_STATE directly to the shared state root.
if [[ ! -e "$backup_dir/xpui.spa" && ! -e "$backup_dir/login.spa" &&
      -s "$SPICETIFY_STATE_DIR/xpui.spa" &&
      -s "$SPICETIFY_STATE_DIR/login.spa" ]]; then
    mkdir -p "$backup_dir"
    cp -n -- "$SPICETIFY_STATE_DIR/xpui.spa" "$SPICETIFY_STATE_DIR/login.spa" "$backup_dir/"
    info "Migrated the existing vanilla .spa backup into $backup_dir."
fi

config_hash="$(sha256sum "$SPICETIFY_CONFIG_FILE" | awk '{print $1}')"
APPLIED_MARKER="$SETUP_DIR/.spicetify-applied"

# The marker alone is not enough: Flatpak can reinstall stock app files while
# leaving Goinfre state intact. Confirm the patched Apps tree and Marketplace
# entry still exist before skipping the apply step.
apps_dir="$SPOTIFY_PATH/Apps"
marketplace_entry="$apps_dir/xpui/spicetify-routes-marketplace.js"
spotify_still_patched=0
if [[ -d "$apps_dir/xpui" && -s "$marketplace_entry" ]] &&
   ! find "$apps_dir" -maxdepth 1 -type f -name '*.spa' -print -quit | grep -q .; then
    spotify_still_patched=1
fi

# Skip patching only when the target Spotify version, Spicetify version,
# config, and patched Marketplace app are all unchanged.
if [[ "$spotify_still_patched" == "1" &&
      -f "$APPLIED_MARKER" &&
      "$(sed -n '1p' "$APPLIED_MARKER")" == "$installed_version" &&
      "$(sed -n '2p' "$APPLIED_MARKER")" == "$cli_version" &&
      "$(sed -n '3p' "$APPLIED_MARKER")" == "$config_hash" ]]; then
    ok "Spicetify and Marketplace are already applied to Spotify $installed_version; skipping patching."
    exit 0
fi

# Adopt a successful manual Spicetify apply from before this launcher tracked
# its state. This is safe only when the Marketplace route exists and both
# vanilla .spa files plus their version/CLI metadata match the active prefs.
adopt_prefs_version="$(awk -F= '$1 == "app.last-launched-version" {
    value = $2
    gsub(/^[[:space:]]*"/, "", value)
    gsub(/"[[:space:]]*$/, "", value)
    print value
    exit
}' "$PREFS_PATH")"
adopt_backup_version="$(ini_value Backup version)"
adopt_backup_cli="$(ini_value Backup with)"
if [[ "$spotify_still_patched" == "1" &&
      -s "$adopt_backup_dir/xpui.spa" &&
      -s "$adopt_backup_dir/login.spa" &&
      "$adopt_backup_version" == "$adopt_prefs_version" &&
      "$adopt_backup_cli" == "$cli_version" ]]; then
    printf '%s\n%s\n%s\n' "$installed_version" "$cli_version" "$config_hash" > "$APPLIED_MARKER.tmp"
    mv -- "$APPLIED_MARKER.tmp" "$APPLIED_MARKER"
    ok "Existing Spicetify and Marketplace patch plus matching vanilla backup detected; recording setup and skipping patching."
    exit 0
fi

# Never rewrite the Spotify app files while a Spotify instance is running.
if flatpak ps --columns=application 2>/dev/null | grep -Fxq "$APP_ID"; then
    die "Spotify is currently running. Close every Spotify window completely, then run ./launch.sh again to apply Spicetify safely."
fi

backup_version="$(ini_value Backup version)"
backup_cli_version="$(ini_value Backup with)"
prefs_version="$(awk -F= '$1 == "app.last-launched-version" {
    value = $2
    gsub(/^[[:space:]]*"/, "", value)
    gsub(/"[[:space:]]*$/, "", value)
    print value
    exit
}' "$PREFS_PATH")"
[[ -n "$prefs_version" ]] ||
    die "Could not read app.last-launched-version from Spotify preferences: $PREFS_PATH"

backup_has_xpui=0
backup_has_login=0
[[ -s "$backup_dir/xpui.spa" ]] && backup_has_xpui=1
[[ -s "$backup_dir/login.spa" ]] && backup_has_login=1
backup_has_spa=0
if [[ "$backup_has_xpui" == "1" && "$backup_has_login" == "1" ]]; then
    backup_has_spa=1
elif [[ "$backup_has_xpui" == "1" || "$backup_has_login" == "1" ]]; then
    die "The existing Spicetify backup is incomplete: expected both $backup_dir/xpui.spa and $backup_dir/login.spa. Refusing to overwrite it."
fi

if [[ "$backup_has_spa" == "1" ]]; then
    [[ "$backup_version" == "$prefs_version" ]] ||
        die "The existing Spicetify backup is for Spotify $backup_version, but the active prefs file records $prefs_version. Refusing to overwrite or apply from a mismatched backup."
    [[ "$backup_cli_version" == "$cli_version" ]] ||
        die "The existing backup was created by Spicetify $backup_cli_version, while the installed CLI is $cli_version. Restore or reinstall the pinned Spotify build before changing Spicetify versions."

    info "Reusing the existing vanilla .spa backup at $backup_dir."
    info "Verified backup version: $backup_version; preferences version: $prefs_version; Spicetify CLI: $cli_version."
    run_with_progress "Applying Spicetify to Spotify" \
        spicetify_cmd apply --no-restart ||
        die "Spicetify apply failed. The CLI will report if its existing backup does not match the Spotify prefs."
else
    info "No vanilla Spicetify .spa backup exists. Creating and verifying it before applying."

    [[ -s "$SPOTIFY_PATH/Apps/xpui.spa" && -s "$SPOTIFY_PATH/Apps/login.spa" ]] ||
        die "The pinned Spotify Apps directory does not contain both vanilla xpui.spa and login.spa archives. Refusing to create an incomplete backup."

    run_with_progress "Creating vanilla Spicetify backup" \
        spicetify_cmd backup ||
        die "Spicetify could not create its vanilla backup. No apply step was attempted."

    [[ -s "$backup_dir/xpui.spa" && -s "$backup_dir/login.spa" ]] ||
        die "Spicetify reported a successful backup, but both archives were not found in $backup_dir. Check the isolated XDG_STATE_HOME path before retrying."

    backup_version="$(ini_value Backup version)"
    backup_cli_version="$(ini_value Backup with)"
    [[ "$backup_version" == "$prefs_version" && "$backup_cli_version" == "$cli_version" ]] ||
        die "The newly created backup metadata does not match Spotify prefs version $prefs_version and Spicetify CLI $cli_version. No apply step was attempted."

    info "Verified vanilla backup: $backup_dir"
    run_with_progress "Applying Spicetify to Spotify" \
        spicetify_cmd apply --no-restart ||
        die "Spicetify apply failed after creating a verified vanilla backup."
fi
backup_version="$(ini_value Backup version)"
backup_cli_version="$(ini_value Backup with)"
[[ "$backup_version" == "$prefs_version" && "$backup_cli_version" == "$cli_version" ]] ||
    die "Spicetify did not record a backup matching preferences version $prefs_version with CLI $cli_version."

config_hash="$(sha256sum "$SPICETIFY_CONFIG_FILE" | awk '{print $1}')"
printf '%s\n%s\n%s\n' "$installed_version" "$cli_version" "$config_hash" > "$APPLIED_MARKER.tmp"
mv -- "$APPLIED_MARKER.tmp" "$APPLIED_MARKER"
ok "Spicetify and Marketplace are applied to Spotify $installed_version."
