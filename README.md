# Spotify + Spicetify user-space launcher

A minimal Ubuntu/Linux setup that runs Spotify with Spicetify from:

```bash
./launch.sh
```

No sudo or administrator access is used. The project keeps its Flatpak installation, Spicetify config, cache and vanilla backup in a writable setup directory (Goinfre by default when available).

## What launch.sh does

1. Selects a writable storage location and initializes the user Flatpak directory.
2. Automatically snapshots your existing themes, extensions, custom apps and portable settings into `backup/profile/` before setup changes anything. This folder is ignored by the public repository.
3. Keeps an existing Spotify installation in the project-owned user Flatpak directory.
4. On a fresh computer, prefers the project's tested Spotify build when it is still available. If that older build is no longer available and no matching local system copy exists, it installs the current Spotify package on Flathub's stable branch, including the runtime dependencies declared by the app.
5. Installs the official Spicetify CLI if it is missing.
6. Keeps Spicetify config and its vanilla backup in the selected setup directory.
7. Creates a vanilla backup only when one is missing or does not match the installed Spotify version. A valid backup is never reset automatically.
8. Restores the saved personal customizations into Spicetify's active config when they are not already present, then installs Marketplace if needed.
9. Applies Spicetify only when the Spotify app is not already patched, verifies the result, and launches Spotify.

The project prefers its tested Spotify build when it can still be obtained. On a clean computer where that older build is no longer available, it falls back to the current Spotify package on Flathub's stable branch instead of requiring an existing system Spotify installation. The Flathub Spotify package is community-maintained and is not verified by, affiliated with, or supported by Spotify. Normal Flatpak updates remain enabled for this fallback installation.

The first run may open Spotify so you can sign in. Close it and run `./launch.sh` again to finish setup and start the customized app. If the user prefs do not exist yet, the launcher opens Spotify for profile creation and resumes setup on the next run.

## Install

Keep this Git repository somewhere persistent (not in Goinfre):

```bash
git clone https://github.com/Nano-Malware/spotify-spicetify-setup.git
cd spotify-spicetify-setup
./launch.sh
```

`install.sh` remains as a backwards-compatible alias for `launch.sh`.

## Storage and account data

- Flatpak app/runtime and Spicetify state: `/goinfre/$USER/spotify-spicetify` when writable and with at least 5 GiB free; otherwise `$HOME/.local/share/spotify-spicetify`.
- Spotify's own profile and prefs remain under `~/.var/app/com.spotify.Client`. They may contain login/session data and are deliberately not copied or moved.
- Existing `~/.config/spicetify` customizations and `~/.local/state/spicetify/Backup` are copied into the project storage when the corresponding destination is absent. Original files are left untouched.
- Goinfre may be cleaned by campus policy. Keep the Git repository and portable customization snapshot in persistent storage.

## Manual maintenance

```bash
./scripts/diagnose.sh            # collect compatibility diagnostics
./scripts/recover_known_good.sh  # interactive recovery of the tested Spotify build
./backup.sh                      # create/update the local private customization backup
./restore.sh                     # interactively restore that snapshot
./apply.sh                       # manually apply Spicetify
```

Spotify installation prefers the tested build when available, can export it from a matching readable system Flatpak repository, and otherwise installs the current Flathub stable release on a clean computer. It never modifies the system Spotify installation. Only the specifically tested pinned build is masked from updates; a current-stable fallback receives normal Flatpak updates.

## Requirements

Linux (tested on Ubuntu), Flatpak, curl, Python 3, tar, unzip, awk, find, flock, and at least 5 GiB free in the selected storage location. Network access to Flathub and GitHub is needed for first-time setup. This project does not install system packages or update glibc.

## Security

Never commit Spotify prefs, credentials, cookies, tokens, the Flatpak app directory, or machine-specific state. `./backup.sh` saves themes, extensions, custom apps and sanitized settings under `backup/profile/`; Marketplace and Spicetify's vanilla Spotify backup are excluded. The snapshot is ignored by this public repository and is intended for a separate private repository. The script does not create a Git repository, commit, or push. Review the snapshot before publishing it privately, and respect the licenses of third-party themes, extensions and custom apps.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for troubleshooting steps and recovery details.
