#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths
require_command curl
require_command unzip
require_spicetify

MARKETPLACE_DIR="$SPICETIFY_CONFIG_DIR/CustomApps/marketplace"
if [[ -d "$MARKETPLACE_DIR" ]]; then
    ok "Spicetify Marketplace already exists."
    exit 0
fi

TMP_SCRIPT="$(mktemp)"
trap 'rm -f "$TMP_SCRIPT"' EXIT
info "Downloading the official Spicetify Marketplace installer..."
curl -fsSL "$MARKETPLACE_INSTALLER_URL" -o "$TMP_SCRIPT"
info "Running the official Marketplace installer with the project-specific Spicetify config directory..."
sh "$TMP_SCRIPT"

[[ -d "$MARKETPLACE_DIR" ]] || die "Marketplace installer finished, but its custom app directory was not found at $MARKETPLACE_DIR"
ok "Spicetify Marketplace installed."
