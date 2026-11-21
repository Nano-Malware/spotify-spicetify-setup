# Spotify user-space launcher

Install and launch Spotify with one command:

```bash
./launch.sh
```

No sudo or administrator access is used.

## What launch.sh does

1. Selects a writable storage location and initializes the project-owned Flatpak user installation.
2. Installs the project's tested Spotify build when available. On a fresh computer where that build cannot be obtained, it installs the current stable Spotify package from Flathub.
3. Installs the official Spicetify CLI into the project-owned setup directory if it is missing.
4. Launches Spotify without modifying Spotify's application files.

The Spicetify CLI is installed and available for manual use, but this launcher intentionally leaves Spotify unmodified. It does not install Marketplace, apply themes, or activate extensions.

The Flathub Spotify package is community-maintained and is not verified by, affiliated with, or supported by Spotify. Normal Flatpak updates remain enabled for the current-stable fallback installation.

## Install

Keep this Git repository somewhere persistent (not in Goinfre):

```bash
git clone https://github.com/Nano-Malware/spotify-spicetify-setup.git
cd spotify-spicetify-setup
./launch.sh
```

`install.sh` remains a backwards-compatible alias for `launch.sh`.

## Storage and account data

- Flatpak app/runtime and Spicetify CLI: `/goinfre/$USER/spotify-spicetify` when writable and with at least 5 GiB free; otherwise `$HOME/.local/share/spotify-spicetify`.
- Spotify's profile and preferences remain under `~/.var/app/com.spotify.Client`. They may contain login/session data and are not copied or moved.
- Goinfre may be cleaned by campus policy. Keep the Git repository in persistent storage.

## Manual maintenance

```bash
./scripts/diagnose.sh            # collect compatibility diagnostics
./scripts/recover_known_good.sh  # install a Spotify build from Flathub when needed
./scripts/recover_known_good.sh --system-copy  # copy this PC's working system Spotify into Goinfre
./scripts/install_spicetify.sh   # install the official Spicetify CLI
```

Spotify installation prefers the tested build when available, can export it from a matching readable system Flatpak repository, and otherwise installs the current Flathub stable release on a clean computer. It never modifies the system Spotify installation. Only the specifically tested pinned build is masked from updates; the current-stable fallback is left unmasked.

When the system-installed Spotify on this same computer is the version you have confirmed works better, run `./scripts/recover_known_good.sh --system-copy` after closing Spotify. This exports the system app into a complete bundle, installs that exact app commit in the project's user Flatpak installation, verifies the commit and runtime match, and masks only the user copy from updates. The system installation is read-only and is not changed.

## Requirements

Linux (tested on Ubuntu), Flatpak, curl, Python 3, tar, unzip, awk, flock, and at least 5 GiB free in the selected storage location. Network access to Flathub and GitHub is needed for first-time setup. This project does not install system packages or update glibc.

## Security

Never commit Spotify preferences, credentials, cookies, tokens, the Flatpak app directory, or machine-specific state. Spotify login and profile data stay in the user's home directory.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for troubleshooting steps and recovery details.
