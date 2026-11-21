# Spotify + Spicetify user-space launcher

A minimal Ubuntu/Linux setup that runs Spotify with Spicetify from one command:

```bash
./launch.sh
```

No sudo or administrator access is used. The project keeps its Flatpak installation, Spicetify config, cache and vanilla backup in a writable setup directory (Goinfre by default when available).

## What launch.sh does

1. Selects a writable storage location and initializes the user Flatpak directory.
2. Checks the Spotify app commit and runtime against the tested baseline:
   - Commit: `d5724652e6dbee2d912d4da426b55d6d16364c405d4f271ca2f04855a7046366`
   - Runtime: `org.freedesktop.Platform/x86_64/24.08`
3. If necessary, recovers that exact build from Flathub or exports it from the matching system Flatpak repository. It never copies random system files or accepts an unverified version.
4. Installs the official Spicetify CLI if it is missing.
5. Keeps Spicetify config and its vanilla backup in the selected setup directory.
6. Creates a vanilla backup only when one is missing or does not match the installed Spotify version. A valid backup is never reset automatically.
7. Installs Marketplace and restores the repository's portable customizations when the user config is empty.
8. Applies Spicetify only when the Spotify app is not already patched, verifies the result, and launches Spotify.

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
./scripts/diagnose.sh       # collect compatibility diagnostics
./scripts/recover_known_good.sh  # interactive pinned-version recovery
./backup.sh                 # update portable themes/extensions/custom apps snapshot
./restore.sh                # interactively restore that snapshot
./apply.sh                  # manually apply Spicetify
```

The recovery script only accepts the pinned app commit and expected runtime. It prefers the exact Flathub commit; if unavailable, it can export a complete bundle from the system Flatpak repository only when that system app is at the exact same commit and its repository objects are readable. It never modifies the system Spotify installation. After recovery it masks normal user-scope updates for Spotify so the tested build is not silently replaced.

## Requirements

Linux (tested on Ubuntu), Flatpak, curl, Python 3, tar, unzip, awk, find, flock, and at least 5 GiB free in the selected storage location. Network access to Flathub and GitHub is needed for first-time setup. This project does not install system packages or update glibc.

## Security

Never commit Spotify prefs, credentials, cookies, tokens, the Flatpak app directory, or machine-specific state. Review `backup/profile/` before pushing: this repository is public, so committed customizations are publicly visible. Respect the licenses of third-party themes, extensions and custom apps.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for the compatibility investigation and recovery details.
