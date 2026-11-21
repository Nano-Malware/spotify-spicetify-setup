# Spotify + Spicetify user-space setup

A no-`sudo` Ubuntu/Linux setup that installs Spotify as a **per-user Flatpak** into a chosen storage directory (Goinfre by default when available), installs the official Spicetify CLI, installs Spicetify Marketplace, and provides portable customization backup/restore scripts.

> **Important storage detail:** `FLATPAK_USER_DIR` controls where Flatpak stores the per-user application and runtime installation. Flatpak still puts the Spotify sandbox profile/config/cache under `~/.var/app/com.spotify.Client` by default. This project deliberately does not symlink or relocate that profile because it may contain login/session data. Keep enough free space in your home directory for Spotify's profile and cache.

## What this project does

- Uses no `sudo`, `su`, `pkexec`, or administrator permissions.
- Uses `/goinfre/$USER/spotify-spicetify` when `/goinfre` is writable and has at least 5 GiB free.
- Otherwise uses `$HOME/.local/share/spotify-spicetify` only when that filesystem has at least 5 GiB free; otherwise it stops without installing.
- Sets `FLATPAK_USER_DIR` so the large per-user Flatpak install is stored under the selected setup directory.
- Installs Spotify from Flathub as a user application; it does not remove or modify the existing system-wide Spotify installation.
- Downloads the latest official Spicetify Linux release for the current CPU architecture, including its required `jsHelper` files.
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
git clone https://github.com/Nano-Malware/spotify-spicetify-setup.git
cd spotify-spicetify-setup
chmod +x install.sh launch.sh backup.sh restore.sh scripts/*.sh
./scripts/diagnose.sh
./install.sh
```

The installer records the selected local storage path in `.setup-dir`. It will ask you to log in to Spotify and close Spotify before applying Spicetify when needed.

Launch the customized per-user Spotify installation with:

```bash
./launch.sh
```

Do not use the old system-wide Spotify desktop launcher if you want the Spicetify-patched user installation.

## Diagnostics and troubleshooting

Before reporting a problem, run:

```bash
./scripts/diagnose.sh
```

It collects the Linux/kernel/glibc versions, Flatpak scope, Spotify versions and commits, Freedesktop runtimes, Mesa extension versions, selected Flatpak GL drivers, Goinfre/home storage usage, and Spicetify installation state. It does not print Spotify prefs contents, credentials, cookies, or session tokens.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for the 42 Ubuntu/AMD compatibility investigation, known-good system Spotify baseline, and recovery notes. To attempt the opt-in recovery of the exact known-good app build in Goinfre, run `./scripts/recover_known_good.sh`. It verifies whether Flathub still serves the pinned commit and otherwise attempts a local bundle export from the known-good system installation. It asks before changing the Goinfre app and never changes the system installation.

## Compatibility recovery

After running diagnostics and confirming that the system Spotify still works, you can attempt the pinned 24.08 recovery:

```bash
./scripts/recover_known_good.sh
```

The script checks the pinned app commit, prompts before changing the Goinfre installation, and verifies the deployed commit/runtime and writable app directory. It does not apply Spicetify automatically: first launch the user app and test login, playback, and rendering. Only then configure/apply Spicetify. The system installation is left untouched.

## Backup and restore

Update the portable customization snapshot:

```bash
./backup.sh
```

Restore the snapshot on a machine where this project and its user-level Spotify installation are already set up:

```bash
./restore.sh
```

Review `backup/profile/` before committing it. A **public repository makes every committed theme, extension, and customization file visible to everyone**. Respect third-party licenses and never commit Spotify prefs, account credentials, browser cookies, access tokens, or session data.

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

The Spicetify patch target is the **user-level** Flatpak deployment. If that deployment is not writable by your account, this project stops; it will not attempt a privileged permission change.

## Known issues

- **Visual glitches on older AMD/kernel combinations:** a newer Flatpak runtime/Mesa may require a newer AMD DRM interface than the host kernel provides. Do not attempt to replace system glibc or system Mesa as an unprivileged workaround. Compare the working system installation with the user installation and follow the documented compatibility investigation.
- **`flatpak kill --user` fails:** `flatpak kill` does not accept `--user`. Inspect `flatpak ps` and kill the intended instance ID.
- **A user app appears "not installed":** check that `FLATPAK_USER_DIR` points to the project's `flatpak/` directory before querying or launching it.
- **Marketplace/Spicetify reports missing `jsHelper` files:** reinstall the Spicetify CLI using `scripts/install_spicetify.sh --update`; the installer must copy the accompanying `jsHelper` directory, not only the binary.
- **Spotify prefs missing:** launch the user-level app with `./launch.sh`, log in, leave it open for at least 60 seconds, close it, then rerun `./scripts/configure.sh`.
- **Marketplace missing:** rerun `./scripts/install_marketplace.sh` after `./install.sh` has configured Spotify and Spicetify.
- **After Spotify updates:** verify that the current Spicetify backup matches the deployed Spotify version before applying. Do not blindly restore an old binary backup against a different Spotify build.

## Security notes

Never commit `~/.var/app/com.spotify.Client`, Spotify's `prefs` file, browser cookies, access tokens, passwords, or the Flatpak installation directory. The `.gitignore` excludes common sensitive-file names, but always inspect `git status` before pushing.
