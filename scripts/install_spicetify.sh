#!/usr/bin/env bash
# Install a checksum-verified Spicetify CLI release into the project setup.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths

require_command curl
require_command sha256sum
require_command tar
require_command chmod
require_command tail
require_command tr
require_command awk

ARCHIVE_NAME="spicetify-${SPICETIFY_VERSION}-linux-amd64.tar.gz"
ARCHIVE_URL="https://github.com/spicetify/cli/releases/download/v${SPICETIFY_VERSION}/${ARCHIVE_NAME}"
TMP_DIR="$(mktemp -d "$SETUP_DIR/.spicetify-install.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT
ARCHIVE_PATH="$TMP_DIR/$ARCHIVE_NAME"
EXTRACT_DIR="$TMP_DIR/extracted"

if [[ -x "$SPICETIFY_BIN" ]]; then
    installed_cli_version="$("$SPICETIFY_BIN" --version 2>/dev/null | tail -n 1 | tr -d '\r')"
    if [[ "$installed_cli_version" == "v$SPICETIFY_VERSION" ||
          "$installed_cli_version" == "$SPICETIFY_VERSION" ]]; then
        ok "Pinned Spicetify CLI $SPICETIFY_VERSION is already installed."
        exit 0
    fi
    warn "Replacing Spicetify CLI ${installed_cli_version:-unknown} with the repository-pinned version $SPICETIFY_VERSION."
fi

info "Downloading the official Spicetify CLI $SPICETIFY_VERSION release."
run_with_progress "Downloading Spicetify CLI $SPICETIFY_VERSION" \
    curl --fail --location --retry 3 --retry-delay 2 --silent --show-error \
    "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
[[ -s "$ARCHIVE_PATH" ]] || die "The Spicetify release archive is empty."

if ! printf '%s  %s\n' "$SPICETIFY_ARCHIVE_SHA256" "$ARCHIVE_PATH" |
    sha256sum --check --status -; then
    die "Spicetify CLI archive checksum verification failed. Refusing to extract it."
fi
ok "Spicetify CLI archive SHA-256 verified."

if ! tar -tzf "$ARCHIVE_PATH" | awk '
    $0 ~ /^\// || $0 ~ /(^|\/)\.\.(\/|$)/ { bad = 1 }
    END { exit bad }
'; then
    die "The Spicetify release archive contains an unsafe path."
fi

mkdir -p "$EXTRACT_DIR"
tar --no-same-owner --no-same-permissions -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
[[ -x "$EXTRACT_DIR/spicetify" ]] ||
    die "The verified Spicetify archive does not contain its expected Linux executable."
for directory in CustomApps Extensions Themes jsHelper; do
    [[ -d "$EXTRACT_DIR/$directory" ]] ||
        die "The verified Spicetify archive is missing its expected $directory directory."
done

# Replace only files owned by the CLI distribution. User Marketplace apps
# and themes live in the separate project XDG config directory and are kept.
rm -rf -- "$BIN_DIR/spicetify" "$BIN_DIR/CustomApps" "$BIN_DIR/Extensions" \
    "$BIN_DIR/Themes" "$BIN_DIR/jsHelper" "$BIN_DIR/globals.d.ts" "$BIN_DIR/css-map.json"
cp -a "$EXTRACT_DIR/." "$BIN_DIR/"
chmod 0755 "$SPICETIFY_BIN"

installed_cli_version="$("$SPICETIFY_BIN" --version 2>/dev/null | tail -n 1 | tr -d '\r')"
[[ "$installed_cli_version" == "v$SPICETIFY_VERSION" ||
   "$installed_cli_version" == "$SPICETIFY_VERSION" ]] ||
    die "Downloaded Spicetify version verification failed. Expected $SPICETIFY_VERSION, got ${installed_cli_version:-unknown}."

ok "Official Spicetify CLI $SPICETIFY_VERSION installed to $BIN_DIR"
"$SPICETIFY_BIN" --version
