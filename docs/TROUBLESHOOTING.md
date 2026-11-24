# Troubleshooting

## Pinned Spotify build

The launcher installs this combination in the project-owned Flatpak user installation:

- Spotify: `1.2.52.442.g01893f92`
- Freedesktop runtime: `org.freedesktop.Platform/x86_64/24.08`
- Mesa extensions: `org.freedesktop.Platform.GL.default//24.08` and `org.freedesktop.Platform.GL.default//24.08extra`, both pinned to Mesa `25.2.6`

This is the combination previously reported to run smoothly on the older PC with Linux kernel 5.15 and AMD DRM 3.42. The 24.08 Mesa branch is selected instead of the newer 25.08 branch that delivered Mesa 26.2.x on the affected machine.

The historical Flatpak OSTree repository archive is built by GitHub Actions from the original Flathub packaging source. Installation also requires the exact Mesa 25.2.6 GL and GL-extra commits to be present in the system Flatpak installation so the project can export them into its user installation; hosts without those deployments cannot use this pinned graphics setup. A single-file `.flatpak` bundle cannot carry the detached metadata this app needs for its Flatpak extra-data source. The repository archive retains that metadata. The proprietary Spotify payload is not hosted in this repository: Flatpak obtains it from the original Snapcraft URL and checks the SHA-256 recorded in the historical Flathub recipe.

> **Security/support warning:** Freedesktop 24.08 reached end of life in September 2026. It no longer receives normal security updates. This project intentionally pins it for compatibility with older graphics hardware; use a currently supported runtime instead when security maintenance is more important than reproducing this older graphics stack.

## Install or repair the pinned build

From the project directory:

```bash
bash ./scripts/install_legacy_spotify.sh
```

The script:

1. Uses the `FLATPAK_USER_DIR` selected by `.setup-dir` (Goinfre by default).
2. Installs Freedesktop 24.08 into that user installation. It checks the system Flatpak installation for the exact Mesa 25.2.6 GL and GL-extra commits, re-exports the installed system Mesa deployment files and metadata as temporary local Flatpak runtime bundles, then installs and pins the resulting commits in the project-owned user installation. It does not modify the system Flathub remote and refuses to use a newer Mesa build.
3. Downloads the release repository archive over HTTPS and checks it against the SHA-256 digest pinned in `scripts/common.sh`.
4. Validates the archive paths, then extracts the repository into the project-owned setup directory.
5. Registers a project-specific per-user Flatpak remote and verifies that the app's extra-data metadata is present.
6. Installs the app from that local repository and verifies the Spotify version, runtime, and origin.
7. Masks the Spotify app and Mesa extension against automatic replacement.

No administrator privileges are requested. The system-wide Spotify installation is not changed.

If the repository archive release asset is not available yet, check the project's GitHub Actions page for the **Build historical Spotify 1.2.52.442 Flatpak** workflow. The installer must not fall back to the current Flathub Spotify version.

## Verify the selected installation

Always select the project-owned user installation:

```bash
IFS= read -r SETUP_DIR < .setup-dir
export FLATPAK_USER_DIR="$SETUP_DIR/flatpak"
flatpak info --user com.spotify.Client
flatpak info --user --show-origin com.spotify.Client
flatpak info --user org.freedesktop.Platform//24.08
flatpak info --user org.freedesktop.Platform.GL.default//24.08
flatpak --gl-drivers
```

Expected Spotify version is `1.2.52.442.g01893f92`; expected runtime is `org.freedesktop.Platform/x86_64/24.08`. The 24.08 Mesa extension should be a Mesa 25.x build, not Mesa 26.1 or newer on an AMD DRM 3.42 kernel.

## Useful launch details

- The historical Flathub recipe requests X11 and PulseAudio. On an X11 desktop, this avoids the newer Wayland-enabled permission set from the current package.
- `flatpak kill` does not accept `--user`. Use `flatpak ps` to identify the running instance, then pass its instance ID to `flatpak kill INSTANCE_ID`.
- Spotify's profile remains under `~/.var/app/com.spotify.Client`. System and user Flatpak copies share this per-app profile path, so close one before testing the other.
- `Failed to load module canberra-gtk-module` and the Ayatana app-indicator deprecation message are warnings; they do not alone prove Spotify failed to launch.
- An AMD DRM warning stating that 3.54 is required indicates that an incompatible newer Mesa extension is active. Do not replace system Mesa or glibc to work around it.
- Do not disable TLS verification or use `curl -k` when downloads fail. Investigate the campus CA/trust configuration instead.

## Safe diagnostics

```bash
./scripts/diagnose.sh
```

The report displays app/runtime/graphics versions and storage information. It intentionally excludes Spotify preferences, credentials, cookies, tokens, and session data.


## Automatic Spicetify and Marketplace setup

The main `./launch.sh` entry point rechecks the host and storage on every launch, verifies/installs the pinned Spicetify CLI `2.46.7`, then runs `scripts/configure_spicetify.sh` after the pinned Spotify app is ready. Spicetify CLI `2.46.7` is downloaded from its versioned Linux release archive and verified against a pinned SHA-256 digest before extraction. Marketplace is pinned to `1.0.12` instead of following the latest release, and its ZIP is also verified against a pinned SHA-256 digest before extraction. It:

- Sets Spicetify's config and state directories under the selected setup directory.
- Points Spicetify at the project-owned Flatpak Spotify files and the existing `~/.var/app/com.spotify.Client/config/spotify/prefs` file.
- Disables the optional Spicetify update check so ordinary launches do not make an extra GitHub API release request.
- Installs Marketplace from its official release only when its app files are absent; it does not overwrite an existing Marketplace directory or other custom apps/themes.
- Uses Spicetify's native first-run setup and applies the configured theme and Marketplace app when needed. The repository does not manage backup files.
- Refuses to patch while Spotify is running. Close Spotify completely and rerun `./launch.sh`.
- Stores an apply marker in the setup directory so unchanged configurations are not patched again on every launch.

If Spotify has not yet written preferences for the pinned version, the launcher opens it once; sign in if needed and close it. The same `./launch.sh` invocation then continues with Spicetify setup and opens the patched Spotify.

The Spicetify CLI may still print a remote CSS-map warning if GitHub rate-limits unauthenticated requests. It falls back to its bundled local CSS map. On Spotify 1.2.63 and older, the warning about not finding the V8 snapshot start marker is also documented by Spicetify as safe to ignore; preprocessing can still complete. A successful `Patching files` completion and `Spicetify and Marketplace are applied` message indicate the patch step completed.


### Spicetify first-run behavior

Spicetify requires its own built-in `backup` command before the first `apply`. This is an upstream CLI requirement, not a repository-managed backup feature. The launcher uses Spicetify's native `backup apply --no-restart` flow for the first patch and `apply --no-restart` for later configuration changes. The repository does not copy, migrate, validate, or delete Spicetify backup files. If Spicetify reports that Spotify is not backed up and cannot be backed up in its current state, the launcher restores the project-owned pinned Spotify app from the verified local Flatpak repository, preserving the separate `~/.var/app/com.spotify.Client` profile, then retries Spicetify's native first-run command.

Before patching, the launcher checks that Spotify's preferences record the pinned app version. If the profile has not been initialized for this Spotify build, it opens Spotify once; after you close it, the launcher completes Spicetify setup and opens the patched app. This keeps the first-run workflow inside one `./launch.sh` invocation.

The launcher leaves `SPICETIFY_STATE` unset and supplies the project-owned XDG directories to the CLI. Do not run a bare `spicetify backup apply` from the shell: that may use the system Spicetify configuration and target the system-wide Spotify installation instead of the project-owned copy.


The Spicetify CLI, Marketplace, and historical Spotify Flatpak repository archives are fetched from fixed release tags and verified against SHA-256 digests recorded by GitHub for their release assets and pinned in `scripts/common.sh`, with expected versions/file layouts checked after extraction. These hashes provide artifact-integrity checks, not publisher signatures or a guarantee that upstream release accounts/artifacts cannot be compromised.
