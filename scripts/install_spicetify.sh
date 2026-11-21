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
require_command install
require_command cp
require_command chmod

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

RELEASE_VERSION=""
if curl -fsSL -H 'Accept: application/json' \
    "$SPICETIFY_RELEASES_URL/latest" -o "$TMP_DIR/release.json"; then
    RELEASE_VERSION="$(python3 - "$TMP_DIR/release.json" <<'PY'
import json
import re
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        release = json.load(handle)
    tag = release.get("tag_name", "")
    match = re.fullmatch(r"v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)", tag)
    if match:
        print(match.group(1))
except (OSError, ValueError, TypeError):
    pass
PY
)" || true
fi

# GitHub's API can rate-limit unauthenticated campus connections. The official
# Spicetify project installer also resolves releases through GitHub's releases
# page rather than requiring the REST API. Keep a verified current release as
# a last-resort fallback so a temporary API/page failure does not brick setup.
if [[ -z "$RELEASE_VERSION" ]]; then
    RELEASE_VERSION="2.46.7"
    warn "Could not resolve the latest Spicetify release; using the last verified stable release v$RELEASE_VERSION."
fi

ASSET_URL="$SPICETIFY_RELEASES_URL/download/v$RELEASE_VERSION/spicetify-$RELEASE_VERSION-linux-$RELEASE_ARCH.tar.gz"
info "Downloading Spicetify v$RELEASE_VERSION for Linux $RELEASE_ARCH..."
curl -fL --retry 3 "$ASSET_URL" -o "$TMP_DIR/spicetify.tar.gz"

mkdir -p "$TMP_DIR/unpacked"
tar -xzf "$TMP_DIR/spicetify.tar.gz" -C "$TMP_DIR/unpacked"
BINARY="$(find "$TMP_DIR/unpacked" -type f -name spicetify -print -quit)"
[[ -n "$BINARY" && -f "$BINARY" ]] || die "The official Spicetify archive did not contain the executable."

# Install the entire official package, not just its executable. This preserves
# any companion files (including jsHelper, when present) beside the CLI.
mkdir -p "$BIN_DIR"
rm -f -- "$SPICETIFY_BIN"
rm -rf -- "$BIN_DIR/jsHelper"
cp -a "$TMP_DIR/unpacked/." "$BIN_DIR/"
if [[ ! -x "$SPICETIFY_BIN" ]]; then
    install -m 0755 "$BINARY" "$SPICETIFY_BIN"
fi
chmod 0755 "$SPICETIFY_BIN"

ok "Installed Spicetify and its companion files to $BIN_DIR"
"$SPICETIFY_BIN" --version
