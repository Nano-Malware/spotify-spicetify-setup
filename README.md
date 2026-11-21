# Spotify + Spicetify user-space launcher

A minimal Ubuntu/Linux setup that runs Spotify with Spicetify from:

```bash
./launch.sh
```

No sudo or administrator access is used. The project keeps its Flatpak installation, Spicetify config, cache and vanilla backup in a writable setup directory (Goinfre by default when available).

## What launch.sh does

1. Selects a writable storage location and initializes the user Flatpak directory.
2. Automatically snapshots your existing themes, extensions, custom apps and portable settings into `backup/profile/` before setup changes anything. This folder is ignored by the public repository.
3. Checks whether Spotify is using the project's tested release and compatible Flatpak runtime.
4. If recovery is needed, it first checks the trusted Flathub remote for that tested release. If the remote no longer provides it, the launcher can export the same release from an existing system Flatpak installation, provided the local Flatpak repository is readable. It stops rather than silently installing an untested version.
5. Installs the official Spicetify CLI if it is missing.
6. Keeps Spicetify config and its vanilla backup in the selected setup directory.
7. Creates a vanilla backup only when one is missing or does not match the installed Spotify version. A valid backup is never reset automatically.
8. Restores the saved personal customizations into Spicetify's active config when they are not already present, then installs Marketplace if needed.
9. Applies Spicetify only when the Spotify app is not already patched, verifies the result, and launches Spotify.

The project uses a tested Spotify build instead of automatically switching to the newest release. This keeps the application and runtime combination predictable. The build identifier is an internal implementation detail; users do not need to find, enter, or change it.

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

Recovery only accepts the project's tested Spotify build. It uses a complete Flatpak bundle when exporting from the system installation, and never modifies the system Spotify installation. After recovery it masks normal user-scope updates for Spotify so the tested build is not silently replaced.

## Requirements

Linux (tested on Ubuntu), Flatpak, curl, Python 3, tar, unzip, awk, find, flock, and at least 5 GiB free in the selected storage location. Network access to Flathub and GitHub is needed for first-time setup. This project does not install system packages or update glibc.

## Security

Never commit Spotify prefs, credentials, cookies, tokens, the Flatpak app directory, or machine-specific state. `./backup.sh` saves themes, extensions, custom apps and sanitized settings under `backup/profile/`; Marketplace and Spicetify's vanilla Spotify backup are excluded. The snapshot is ignored by this public repository and is intended for a separate private repository. The script does not create a Git repository, commit, or push. Review the snapshot before publishing it privately, and respect the licenses of third-party themes, extensions and custom apps.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for troubleshooting steps and recovery details.
