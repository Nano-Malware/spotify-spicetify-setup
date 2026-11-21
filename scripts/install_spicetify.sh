#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths

require_command curl
require_command python3
require_command tar
require_command find

FORCE_UPDATE="${1:-}"
if [[ -x "$SPICETIFY_BIN" && "$FORCE_UPDATE" != "--update" ]]; then
    ok "Spicetify CLI already exists: $SPICETIFY_BIN"
    "$SPICETIFY_BIN" --version
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) RELEASE_ARCH="amd64" ;;
    aarch64|arm64) RELEASE_ARCH="arm64" ;;
    *) die "Unsupported CPU architecture for the Spicetify Linux release: $ARCH" ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

info "Checking the latest official Spicetify CLI release..."
curl -fsSL "$SPICETIFY_RELEASE_API" -o "$TMP_DIR/release.json"
RELEASE_LINE="$(python3 - "$TMP_DIR/release.json" "$RELEASE_ARCH" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    release = json.load(handle)
arch = sys.argv[2]
needle = f"linux-{arch}.tar.gz"
assets = [item for item in release.get("assets", []) if item.get("name", "").endswith(needle)]
if not assets:
    raise SystemExit(f"No official Linux {arch} tar.gz asset found in the latest release.")
print(release.get("tag_name", ""))
print(assets[0].get("browser_download_url", ""))
PY
)" || die "Could not identify a matching Spicetify release asset."
RELEASE_TAG="$(printf '%s\n' "$RELEASE_LINE" | sed -n '1p')"
ASSET_URL="$(printf '%s\n' "$RELEASE_LINE" | sed -n '2p')"
[[ -n "$RELEASE_TAG" && "$ASSET_URL" == https://github.com/spicetify/cli/releases/download/* ]] || die "The Spicetify release metadata was incomplete."

info "Downloading Spicetify $RELEASE_TAG for Linux $RELEASE_ARCH..."
curl -fL --retry 3 "$ASSET_URL" -o "$TMP_DIR/spicetify.tar.gz"
mkdir -p "$TMP_DIR/unpacked"
tar -xzf "$TMP_DIR/spicetify.tar.gz" -C "$TMP_DIR/unpacked"
BINARY="$(find "$TMP_DIR/unpacked" -type f -name spicetify -print -quit)"
[[ -n "$BINARY" && -f "$BINARY" ]] || die "The downloaded archive did not contain the Spicetify executable."

# Spicetify requires jsHelper support files beside the executable at runtime.
# Copying only the binary causes apply errors for homeConfig.js and expFeatures.js.
HELPER_DIR="$(find "$TMP_DIR/unpacked" -type d -name jsHelper -print -quit)"
[[ -n "$HELPER_DIR" && -d "$HELPER_DIR" ]] || die "The official archive did not contain the required jsHelper directory."
for helper in homeConfig.js expFeatures.js; do
    [[ -s "$HELPER_DIR/$helper" ]] || die "The official jsHelper directory is missing $helper."
done

install -m 0755 "$BINARY" "$SPICETIFY_BIN"
rm -rf -- "$BIN_DIR/jsHelper"
cp -a "$HELPER_DIR" "$BIN_DIR/jsHelper"

ok "Installed Spicetify and jsHelper support files to $BIN_DIR"
"$SPICETIFY_BIN" --version
