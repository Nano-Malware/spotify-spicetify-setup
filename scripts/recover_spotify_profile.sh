#!/usr/bin/env bash
# Stop the project-owned Spotify instance and recover stale Chromium locks
# left in the shared Spotify profile when moving between 42 workstations.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths

require_command awk
require_command readlink
require_command sleep

read_running_instances() {
    flatpak ps --columns=instance,application 2>/dev/null ||
        die "Could not inspect running Flatpak instances. Refusing to modify Spotify's shared profile."
}

running_rows="$(read_running_instances)"
mapfile -t spotify_instances < <(
    awk -v app="$APP_ID" 'NR > 1 && $2 == app { print $1 }' <<< "$running_rows"
)

project_instances=()
other_installation_running=0
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

for instance_id in "${spotify_instances[@]}"; do
    info_file="$runtime_dir/.flatpak/$instance_id/info"
    [[ -r "$info_file" ]] ||
        die "Spotify instance $instance_id is running, but its Flatpak metadata cannot be read. Close Spotify manually and rerun the launcher."

    app_path="$(awk -F= '
        /^\[Instance\]$/ { in_instance = 1; next }
        /^\[/ && in_instance { exit }
        in_instance && $1 == "app-path" {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$info_file")"

    case "$app_path" in
        "$FLATPAK_USER_DIR/app/$APP_ID/"*)
            project_instances+=("$instance_id")
            ;;
        *)
            warn "Spotify is also running from another Flatpak installation (instance $instance_id, app path: ${app_path:-unknown}). Leaving that instance untouched."
            other_installation_running=1
            ;;
    esac
done

for instance_id in "${project_instances[@]}"; do
    warn "Spotify is already running from this project's Flatpak installation. Stopping local instance $instance_id before setup."
    flatpak kill "$instance_id" ||
        die "Could not stop project-owned Spotify instance $instance_id."

    stopped=0
    for ((attempt = 0; attempt < 15; attempt++)); do
        running_rows="$(read_running_instances)"
        if ! awk -v id="$instance_id" 'NR > 1 && $1 == id { found = 1 } END { exit !found }' <<< "$running_rows"; then
            stopped=1
            break
        fi
        sleep 1
    done

    [[ "$stopped" == "1" ]] ||
        die "Spotify instance $instance_id did not stop. Close it manually before rerunning ./launch.sh."
    ok "Stopped the existing project-owned Spotify instance."
done

if [[ "$other_installation_running" == "1" ]]; then
    die "Another Spotify installation is still running on this workstation. Close it manually before rerunning ./launch.sh; it was not killed."
fi

profile_cache="$HOME/.var/app/$APP_ID/cache/spotify"
[[ -d "$profile_cache" ]] || exit 0

lock_names=(SingletonLock SingletonCookie SingletonSocket)
stale_links=()

for lock_name in "${lock_names[@]}"; do
    lock_path="$profile_cache/$lock_name"

    if [[ -L "$lock_path" ]]; then
        target="$(readlink -- "$lock_path" 2>/dev/null || printf unknown)"
        warn "Found Chromium singleton symlink: $lock_name -> $target"
        stale_links+=("$lock_name")
    elif [[ -e "$lock_path" ]]; then
        warn "Found a non-symlink Chromium singleton path: $lock_path. Leaving it untouched."
    fi
done

(("${#stale_links[@]}" > 0)) || exit 0

warn "Spotify's profile may be shared with another 42 workstation. Its lock symlinks can belong to a still-running Spotify session elsewhere."
if ! read -r -p "Have you completely closed Spotify on every other 42 workstation? [y/N] " answer; then
    answer=""
fi

case "$answer" in
    y|Y|yes|YES|Yes)
        ;;
    *)
        die "No lock files were changed. Close Spotify on the other workstation(s), then rerun ./launch.sh."
        ;;
esac

running_rows="$(read_running_instances)"
if awk -v app="$APP_ID" 'NR > 1 && $2 == app { found = 1 } END { exit !found }' <<< "$running_rows"; then
    die "Spotify started again on this workstation. No Chromium singleton symlinks were removed."
fi

for lock_name in "${stale_links[@]}"; do
    lock_path="$profile_cache/$lock_name"
    if [[ -L "$lock_path" ]]; then
        rm -f -- "$lock_path"
        info "Removed stale Chromium singleton symlink: $lock_name"
    elif [[ -e "$lock_path" ]]; then
        warn "$lock_name changed into a non-symlink while recovery was running; leaving it untouched."
    fi
done

ok "Chromium singleton symlink recovery completed. Spotify will recreate these links on launch."
