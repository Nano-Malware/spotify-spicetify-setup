# Spotify user-space launcher

Install and launch the compatible Spotify build with one command:

```bash
./launch.sh
```

No sudo or administrator access is needed on the user's machine. The separate GitHub Actions build uses a hosted runner to prepare the repository archive.

## What launch.sh does

1. Selects a writable storage location and initializes the project-owned Flatpak user installation.
2. Downloads and installs Spotify **1.2.52.442** from a checksum-verified Flatpak repository archive built from the historical official Flathub packaging recipe.
3. Installs the Freedesktop **24.08** runtime into the project-owned Goinfre installation. For graphics, it verifies the existing system Mesa **25.2.6** `24.08` and `24.08extra` deployments, re-exports their installed files and metadata into temporary local runtime bundles, and pins the resulting commits in Goinfre. It does not download the newer incompatible Flathub Mesa branch or modify system Flatpak.
4. Verifies the Spotify version, runtime, and Mesa version, then masks the Spotify app and Mesa extension to avoid incompatible automatic updates.
5. Installs the official Spicetify CLI if it is missing.
6. Configures Spicetify to use the Goinfre Spotify files and the existing home-directory Spotify preferences. It disables the CLI's optional update check to avoid an unnecessary GitHub API request.
7. Installs the official Marketplace release if its files are missing, preserving existing custom apps and themes.
8. Initializes Spotify's profile on its first launch when needed, then uses Spicetify's native first-time setup and applies Marketplace. A state marker avoids repeating the patch when the Spotify version and configuration have not changed. The repository does not manage, copy, migrate, or delete backup files. If Spicetify detects an incomplete patched Spotify app without a usable native state, the launcher reinstalls only the pinned project-owned app from its verified local Flatpak repository and retries; the user's Spotify profile is kept.

The selected Spotify build and 24.08 graphics stack reproduce the combination that previously worked smoothly on the user's older computer. Spicetify and Marketplace are configured and applied automatically by the launcher.

The Flatpak repository is rebuilt by GitHub Actions from the historical Flathub packaging source. This app uses Flatpak extra-data, so the project distributes the OSTree repository archive rather than a single-file `.flatpak` bundle; the repository retains the metadata required for the extra-data download. The proprietary Spotify payload is fetched directly from its original Snapcraft source during installation and verified using the SHA-256 recorded in the historical Flathub manifest. The Flathub packaging is community-maintained and is not verified by, affiliated with, or supported by Spotify.

## Compatibility and security warning

This project deliberately pins Freedesktop Platform 24.08 to reproduce a graphics/runtime combination that worked on older AMD hardware. **Freedesktop 24.08 reached end of life in September 2026 and no longer receives normal security updates.** Use this compatibility build only when that trade-off is acceptable; it is not the recommended choice for users who need a currently supported runtime. The project does not silently switch to a newer runtime because doing so could reintroduce the graphics incompatibility this setup is intended to avoid.

## Install

Keep this Git repository somewhere persistent (not in Goinfre):

```bash
git clone https://github.com/Nano-Malware/spotify-spicetify-setup.git
cd spotify-spicetify-setup
./launch.sh
```

`install.sh` remains a backwards-compatible alias for `launch.sh`.

The first installation downloads the old Spotify build and 24.08 runtime. The Mesa 25.2.6 extensions are exported from the matching system Flatpak installation when those exact commits are present. It may take several minutes and uses several gigabytes of Goinfre storage.

The historical Flatpak repository archive is built and published by this repository's GitHub Actions workflow. Normal users do **not** need GitHub CLI or a GitHub account. The installer downloads the published archive automatically. You can check its publication status on the [Spotify 1.2.52.442 release page](https://github.com/Nano-Malware/spotify-spicetify-setup/releases/tag/spotify-1.2.52.442). If the release is not published yet, the installer stops safely instead of falling back to the current Spotify build.

## Maintainers: build or republish the historical repository

The workflow normally starts when its workflow file changes. To trigger it manually or inspect its runs, maintainers can use GitHub CLI:

```bash
gh workflow run build-spotify-1.2.52.yml --ref main
gh run list --workflow build-spotify-1.2.52.yml --limit 5
```


## Storage and account data

- Spotify app, runtime, Mesa extension, local Flatpak repository, and Spicetify CLI: `/goinfre/$USER/spotify-spicetify` when writable and with at least 5 GiB free; otherwise `$HOME/.local/share/spotify-spicetify`.
- Spotify's profile and preferences remain under `~/.var/app/com.spotify.Client`. They may contain login/session data and are not copied or moved.
- Goinfre may be cleaned by campus policy. Keep the Git repository in persistent storage.

## Manual maintenance

```bash
./scripts/diagnose.sh                 # collect compatibility diagnostics
bash ./scripts/install_legacy_spotify.sh # install/verify the pinned compatible Spotify build
./scripts/install_spicetify.sh        # install the official Spicetify CLI
```

The historical Spotify app and Mesa extension are masked in the project-owned user installation. This prevents an update from silently replacing the tested versions. The system-wide Spotify installation is never modified.

## Requirements

Linux x86_64, Flatpak 1.14 or newer, curl, sha256sum, tar, awk, grep, flock, unzip (only if Marketplace must be installed), the `script` utility, and at least 5 GiB free in the selected storage location. Network access to GitHub, Flathub, and Snapcraft is needed for first-time setup. This project does not install system packages or update glibc.

## Security

Never commit Spotify preferences, credentials, cookies, tokens, the Flatpak app directory, or machine-specific state. Spotify login and profile data stay in the user's home directory.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for troubleshooting steps and recovery details.
