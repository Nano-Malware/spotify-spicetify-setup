#!/usr/bin/env bash
# Verify storage fallback for fresh installs without moving an existing app.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
cat > "$TMP_ROOT/bin/df" <<'DF'
#!/usr/bin/env bash
set -Eeuo pipefail
target="${@: -1}"
case "$target" in
    *low-space*|*goinfre*) available=1000000 ;;
    *) available=10000000 ;;
esac
printf 'Filesystem 1K-blocks Used Available Use%% Mounted on\n'
printf '/dev/mock 12000000 %s %s 90%% /\n' "$((12000000 - available))" "$available"
DF
chmod +x "$TMP_ROOT/bin/df"

make_project() {
    local project="$1"
    mkdir -p "$project/scripts"
    cp "$ROOT_DIR/scripts/common.sh" "$project/scripts/common.sh"
    cp "$ROOT_DIR/scripts/detect.sh" "$project/scripts/detect.sh"
}

# Fresh install: the remembered preferred location has less than 5 GiB,
# so the detector should select home storage when it has enough free space.
FRESH_PROJECT="$TMP_ROOT/fresh-project"
FRESH_HOME="$TMP_ROOT/fresh-home"
FRESH_SETUP="$TMP_ROOT/goinfre/spotify-spicetify"
mkdir -p "$FRESH_HOME" "$(dirname -- "$FRESH_SETUP")"
make_project "$FRESH_PROJECT"
printf '%s\n' "$FRESH_SETUP" > "$FRESH_PROJECT/.setup-dir"

HOME="$FRESH_HOME" PATH="$TMP_ROOT/bin:$PATH" \
    bash "$FRESH_PROJECT/scripts/detect.sh" > "$TMP_ROOT/fresh.log" 2>&1
EXPECTED_HOME_SETUP="$FRESH_HOME/.local/share/spotify-spicetify"
[[ "$(cat "$FRESH_PROJECT/.setup-dir")" == "$EXPECTED_HOME_SETUP" ]]
grep -Fq "Falling back to $EXPECTED_HOME_SETUP" "$TMP_ROOT/fresh.log"

# Existing install: even with low free space, keep the current location so
# the app is not split between two independent Flatpak user installations.
EXISTING_PROJECT="$TMP_ROOT/existing-project"
EXISTING_HOME="$TMP_ROOT/existing-home"
EXISTING_SETUP="$TMP_ROOT/low-space/spotify-spicetify"
mkdir -p "$EXISTING_HOME" "$EXISTING_SETUP/flatpak/app/com.spotify.Client"
make_project "$EXISTING_PROJECT"
printf '%s\n' "$EXISTING_SETUP" > "$EXISTING_PROJECT/.setup-dir"

HOME="$EXISTING_HOME" PATH="$TMP_ROOT/bin:$PATH" \
    bash "$EXISTING_PROJECT/scripts/detect.sh" > "$TMP_ROOT/existing.log" 2>&1
[[ "$(cat "$EXISTING_PROJECT/.setup-dir")" == "$EXISTING_SETUP" ]]
grep -Fq 'Keeping it in place to avoid silently creating a second installation' "$TMP_ROOT/existing.log"

printf '%s\n' '[PASS] Fresh installation falls back to home storage when the preferred location is low on space.'
printf '%s\n' '[PASS] Existing Flatpak installation remains at its current path when storage is low.'
