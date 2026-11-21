#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ "$(id -u)" -eq 0 ]]; then
    printf '[FAIL] Run this installer as your normal user, not as root. No sudo is required.\n' >&2
    exit 1
fi
source "$PROJECT_DIR/scripts/common.sh"

printf '\nSpotify + Spicetify user-space installer\n'
printf '=======================================\n\n'

require_command flatpak
require_command curl
require_command python3
require_command tar
require_command unzip
require_command awk
require_command df

"$PROJECT_DIR/scripts/detect.sh"
source "$PROJECT_DIR/scripts/common.sh"
init_paths

info "Step 1/5: install Spotify in the Goinfre-backed user Flatpak installation."
"$PROJECT_DIR/scripts/install_spotify.sh"

info "Step 2/5: install the official Spicetify CLI."
"$PROJECT_DIR/scripts/install_spicetify.sh"

info "Step 3/5: configure Spicetify for this user-level Spotify."
"$PROJECT_DIR/scripts/configure.sh"

info "Step 4/5: install Marketplace."
"$PROJECT_DIR/scripts/install_marketplace.sh"

info "Step 5/5: apply and verify."
spicetify apply
"$PROJECT_DIR/scripts/verify.sh"

info "Saving a portable customization backup in this Git repository."
"$PROJECT_DIR/backup.sh"

printf '\n'
ok "Setup completed."
printf 'Launch customized Spotify with: %s/launch.sh\n' "$PROJECT_DIR"
printf 'Create/update your portable customization backup with: %s/backup.sh\n' "$PROJECT_DIR"
printf '\nRemember: the Goinfre installation may be temporary. Push this Git repository to a private GitHub repo after reviewing the backup contents.\n'
