#!/usr/bin/env bash
# Exercise launch.sh's first-run initialization and error reporting without Flatpak.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

setup_case() {
    local case_dir="$1"
    mkdir -p "$case_dir/scripts" "$case_dir/bin" "$case_dir/setup/bin"
    cp "$ROOT_DIR/launch.sh" "$case_dir/launch.sh"

    cat > "$case_dir/scripts/common.sh" <<'COMMON'
#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_ID="com.spotify.Client"
TARGET_SPOTIFY_VERSION="1.2.52.442.g01893f92"
SETUP_DIR="$TEST_SETUP"
SPICETIFY_BIN="$SETUP_DIR/bin/spicetify"
info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
init_paths() { mkdir -p "$SETUP_DIR/bin"; }
spotify_is_installed() { return 0; }
spotify_installed_version() { printf '%s\n' "$TARGET_SPOTIFY_VERSION"; }
ensure_user_spotify_installed() { return 0; }
COMMON
    cat > "$case_dir/scripts/detect.sh" <<'DETECT'
#!/usr/bin/env bash
exit 0
DETECT
    cat > "$case_dir/scripts/install_legacy_spotify.sh" <<'INSTALL'
#!/usr/bin/env bash
exit 0
INSTALL
    cat > "$case_dir/scripts/install_spicetify.sh" <<'SPICETIFY_INSTALL'
#!/usr/bin/env bash
exit 0
SPICETIFY_INSTALL
    cat > "$case_dir/scripts/configure_spicetify.sh" <<'CONFIGURE'
#!/usr/bin/env bash
set -Eeuo pipefail
count=0
[[ ! -f "$TEST_STATE/configure-count" ]] || count="$(cat "$TEST_STATE/configure-count")"
count=$((count + 1))
printf '%s\n' "$count" > "$TEST_STATE/configure-count"
if [[ "$count" == "1" ]]; then
    exit 10
fi
exit 0
CONFIGURE
    cat > "$case_dir/bin/flatpak" <<'FLATPAK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$TEST_STATE/flatpak.log"
if [[ "${1:-}" == "run" ]]; then
    count=0
    [[ ! -f "$TEST_STATE/flatpak-run-count" ]] || count="$(cat "$TEST_STATE/flatpak-run-count")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$TEST_STATE/flatpak-run-count"
    if [[ "$count" == "1" && "${TEST_FIRST_RUN_STATUS:-0}" != "0" ]]; then
        exit "$TEST_FIRST_RUN_STATUS"
    fi
fi
exit 0
FLATPAK
    chmod +x "$case_dir/bin/flatpak"
}

# The first Spotify launch must produce an actionable error if Flatpak fails.
FAIL_DIR="$TMP_ROOT/fail"
FAIL_SETUP="$FAIL_DIR/setup"
mkdir -p "$FAIL_SETUP/bin" "$TMP_ROOT/fail-state"
touch "$FAIL_SETUP/bin/spicetify"
setup_case "$FAIL_DIR"
export TEST_SETUP="$FAIL_SETUP"
export TEST_STATE="$TMP_ROOT/fail-state"
export TEST_FIRST_RUN_STATUS=42
if PATH="$FAIL_DIR/bin:$PATH" TEST_SETUP="$FAIL_SETUP" TEST_STATE="$TEST_STATE" \
    bash "$FAIL_DIR/launch.sh" >"$TMP_ROOT/fail.log" 2>&1; then
    cat "$TMP_ROOT/fail.log"
    printf '%s\n' '[FAIL] launch.sh unexpectedly succeeded after Spotify returned 42.' >&2
    exit 1
fi
grep -Fq 'Spotify exited with status 42 during first-run profile initialization' "$TMP_ROOT/fail.log"

# If Spotify initializes successfully, launch.sh must retry configuration
# and then perform the normal launch.
OK_DIR="$TMP_ROOT/success"
OK_SETUP="$OK_DIR/setup"
mkdir -p "$OK_SETUP/bin" "$TMP_ROOT/success-state"
touch "$OK_SETUP/bin/spicetify"
setup_case "$OK_DIR"
export TEST_SETUP="$OK_SETUP"
export TEST_STATE="$TMP_ROOT/success-state"
export TEST_FIRST_RUN_STATUS=0
PATH="$OK_DIR/bin:$PATH" TEST_SETUP="$OK_SETUP" TEST_STATE="$TEST_STATE" \
    bash "$OK_DIR/launch.sh" >"$TMP_ROOT/success.log" 2>&1 || {
        cat "$TMP_ROOT/success.log"
        printf '%s\n' '[FAIL] First-run initialization did not complete.' >&2
        exit 1
    }

[[ "$(cat "$TEST_STATE/configure-count")" == "2" ]]
[[ "$(cat "$TEST_STATE/flatpak-run-count")" == "2" ]]
grep -Fq 'Launching Spotify 1.2.52.442.g01893f92' "$TMP_ROOT/success.log"

printf '%s\n' '[PASS] First-run Flatpak failure is reported with a manual recovery command.'
printf '%s\n' '[PASS] Successful profile initialization retries configuration and launches Spotify.'
