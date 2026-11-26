#!/usr/bin/env bash
# Verify low-space cleanup is limited to Spotify's disposable cache.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home/.var/app/com.spotify.Client/cache/spotify" "$TMP_ROOT/home/.var/app/com.spotify.Client/config/spotify"

cat > "$TMP_ROOT/bin/df" <<'DF'
#!/usr/bin/env bash
set -Eeuo pipefail
profile="${@: -1}"
if [[ -d "$profile/cache/spotify" ]]; then available=200000; else available=700000; fi
printf 'Filesystem 1K-blocks Used Available Use%% Mounted on\n'
printf '/dev/mock 1000000 800000 %s 80%% /\n' "$available"
DF
cat > "$TMP_ROOT/bin/flatpak" <<'FLATPAK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${TEST_SPOTIFY_RUNNING:-0}" == "1" ]]; then printf 'Application\ncom.spotify.Client\n'; else printf 'Application\n'; fi
FLATPAK
chmod +x "$TMP_ROOT/bin/df" "$TMP_ROOT/bin/flatpak"
export HOME="$TMP_ROOT/home"
export PATH="$TMP_ROOT/bin:$PATH"
export TEST_SPOTIFY_RUNNING=0
printf 'keep-me\n' > "$HOME/.var/app/com.spotify.Client/config/spotify/prefs"
printf 'cached\n' > "$HOME/.var/app/com.spotify.Client/cache/spotify/blob"
(
    source "$ROOT_DIR/scripts/common.sh"
    cleanup_spotify_cache_if_low_space
)
[[ ! -e "$HOME/.var/app/com.spotify.Client/cache/spotify" ]]
grep -Fxq 'keep-me' "$HOME/.var/app/com.spotify.Client/config/spotify/prefs"
mkdir -p "$HOME/.var/app/com.spotify.Client/cache/spotify"
printf 'keep-cache\n' > "$HOME/.var/app/com.spotify.Client/cache/spotify/blob"
export TEST_SPOTIFY_RUNNING=1
(
    source "$ROOT_DIR/scripts/common.sh"
    cleanup_spotify_cache_if_low_space
)
[[ -f "$HOME/.var/app/com.spotify.Client/cache/spotify/blob" ]]
printf '%s\n' '[PASS] Low-space recovery clears only Spotify cache and preserves preferences.'
printf '%s\n' '[PASS] Cache cleanup is skipped while Spotify is running.'
