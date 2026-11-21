#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
init_paths

require_command curl
require_command script
require_command grep
require_command chmod

# The official installer always installs to "$HOME/.spicetify" and asks
# interactive questions through /dev/tty. Give it an isolated HOME under the
# project-owned Goinfre directory and a temporary PTY, so it cannot discover
# or update another Spicetify installation or touch the user's shell config.
INSTALL_HOME="$SETUP_DIR/spicetify-installer-home"
INSTALL_BIN="$INSTALL_HOME/.spicetify/spicetify"
INSTALL_LOG="$SETUP_DIR/spicetify-installer.log"
CLEAN_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [[ -x "$SPICETIFY_BIN" ]]; then
    ok "Spicetify CLI is already installed in the project directory."
    "$SPICETIFY_BIN" --version
    exit 0
fi

mkdir -p "$INSTALL_HOME"
info "Installing Spicetify with the official installer into $INSTALL_HOME..."
info "Marketplace is intentionally not installed; this launcher installs the CLI only."

# 'script' supplies the TTY required by the upstream installer. The single
# 'n' answers its Marketplace prompt; it does not accept or run any other
# interactive action. HOME and PATH are isolated from existing installations.
if ! printf 'n\n' | script -q -e -c \
    "env HOME='$INSTALL_HOME' PATH='$CLEAN_PATH' SHELL=/bin/sh sh -c 'curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh'" \
    /dev/null 2>&1 | tee "$INSTALL_LOG"; then
    warn "The official Spicetify installer failed. Details are saved in: $INSTALL_LOG"
    die "Could not install Spicetify. Check your network connection and the installer log."
fi

[[ -x "$INSTALL_BIN" ]] || {
    warn "The official installer completed without creating its expected executable."
    die "Spicetify was not installed. Check $INSTALL_LOG."
}

# Move the official installation into the path shared by the rest of this
# project. Keep the complete package, not only the executable.
mkdir -p "$BIN_DIR"
cp -a "$INSTALL_HOME/.spicetify/." "$BIN_DIR/"
chmod 0755 "$SPICETIFY_BIN"
ok "Official Spicetify CLI installed to $BIN_DIR"
"$SPICETIFY_BIN" --version
