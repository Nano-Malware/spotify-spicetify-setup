# Spotify + Spicetify user-space setup

A no-`sudo` Ubuntu/Linux setup that installs Spotify as a **per-user Flatpak** into a chosen storage directory (Goinfre by default when available), installs the official Spicetify CLI, installs Spicetify Marketplace, and provides portable customization backup/restore scripts.

> **Important storage detail:** `FLATPAK_USER_DIR` controls where Flatpak stores the per-user application and runtime installation. Flatpak still puts the Spotify sandbox profile/config/cache under `~/.var/app/com.spotify.Client` by default. This project deliberately does not symlink or relocate that profile because it may contain login/session data. Keep enough free space in your home directory for Spotify's profile and cache.

## What this project does

- Uses no `sudo`, `su`, `pkexec`, or administrator permissions.
- Uses `/goinfre/$USER/spotify-spicetify` when `/goinfre` is writable and has at least 5 GiB free.
- Otherwise uses `$HOME/.local/share/spotify-spicetify` only when that filesystem has at least 5 GiB free; otherwise it stops without installing.
- Sets `FLATPAK_USER_DIR` so the large per-user Flatpak install is stored under the selected setup directory.
- Installs Spotify from Flathub as a user application; it does not remove or modify the existing system-wide Spotify installation.
- Downloads the latest official Spicetify Linux release for the current CPU architecture.
- Installs Marketplace using the official Spicetify Marketplace installer.
- Uses a project-specific XDG config/cache/data directory for Spicetify.
- Backs up themes, extensions, custom apps and a sanitized Spicetify config to `backup/profile/`.
- Does **not** back up Spotify prefs, login credentials, session tokens, Spotify cache, or Spicetify's vanilla Spotify binary backup.

## Requirements

- Linux (first version targets Ubuntu/Debian-based distributions).
- `flatpak`, `curl`, `python3`, `tar`, `awk`, `df`, `stat`, `chmod`, and standard shell utilities.
- A writable storage location with at least 5 GiB free for the Flatpak install/runtime.
- Network access to Flathub and GitHub.
- A Spotify account. On a new machine you must log in again; account credentials are never copied by this project.

This project does not install system packages. If a required tool is missing and you cannot install it without administrator rights, ask your system administrator.

## Install

Clone this repository somewhere persistent (not in Goinfre):

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/spotify-spicetify-setup.git
cd spotify-spicetify-setup
chmod +x install.sh launch.sh backup.sh restore.sh scripts/*.sh
./install.sh
```

The installer records the selected local storage path in `.setup-dir`, which is ignored by Git. It will ask you to log in to Spotify and close Spotify before applying Spicetify when needed.

Launch the customized per-user Spotify installation with:

```bash
./launch.sh
```

Do not use the old system-wide Spotify desktop launcher if you want the Spicetify-patched user installation.

## Backup and restore

Update the portable customization snapshot:

```bash
./backup.sh
```

Restore the snapshot on a machine where this project and its user-level Spotify installation are already set up:

```bash
./restore.sh
```

Review `backup/profile/` before committing it. A **private GitHub repository** is recommended if you store Marketplace downloads or third-party themes/extensions there. Respect the licenses of third-party customization files.

On another computer:

1. Clone this repository.
2. Run `./install.sh` to install Spotify and Spicetify into that computer's chosen writable location.
3. Log in to Spotify on that computer.
4. Run `./restore.sh` to restore the customizations from Git.

Goinfre is not portable and may be cleaned. The repository and the portable snapshot must remain in persistent storage (such as your home directory or GitHub).

## Choose another installation location

You can explicitly choose a writable mounted directory with at least 5 GiB free:

```bash
SPOTIFY_SETUP_DIR=/path/to/writable/disk/spotify-spicetify ./install.sh
```

The selected path is local machine state and is not committed to Git.

## Existing system Spotify

This project leaves the current system-wide Spotify installation untouched. Both Flatpak installations use the same application ID, so Spotify's per-app profile directory (`~/.var/app/com.spotify.Client`) may be shared by the system and user installations. Do not run both installations simultaneously while patching.

The Spicetify patch target is the **user-level** Flatpak deployment. If that deployment is not writable by your account, the script stops; it will not attempt a privileged permission change.

## Troubleshooting

- **Not enough disk space:** choose another writable mount with `SPOTIFY_SETUP_DIR`. The script requires 5 GiB free before installing.
- **Spotify prefs missing:** launch the user-level app with `./launch.sh`, log in, leave it open for at least 60 seconds, close it, then rerun `./scripts/configure.sh`.
- **Marketplace missing:** rerun `./scripts/install_marketplace.sh` after `./install.sh` has configured Spotify and Spicetify.
- **After Spotify updates:** try `spicetify backup apply` using this project's Spicetify binary and project XDG config. The simple equivalent is:

  ```bash
  SETUP_DIR="$(cat .setup-dir)"
  FLATPAK_USER_DIR="$SETUP_DIR/flatpak" \
  XDG_CONFIG_HOME="$SETUP_DIR/xdg-config" \
  "$SETUP_DIR/bin/spicetify" backup apply
  ```

## Security notes

Never commit `~/.var/app/com.spotify.Client`, Spotify's `prefs` file, browser cookies, access tokens, passwords, or the Flatpak installation directory. The `.gitignore` excludes common sensitive-file names, but always inspect `git status` before pushing.
