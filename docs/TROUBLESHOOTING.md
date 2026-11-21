# Troubleshooting

## Pinned Spotify build

The launcher installs this combination in the project-owned Flatpak user installation:

- Spotify: `1.2.52.442.g01893f92`
- Freedesktop runtime: `org.freedesktop.Platform/x86_64/24.08`
- Mesa extension: `org.freedesktop.Platform.GL.default//24.08`

This is the combination previously reported to run smoothly on the older PC with Linux kernel 5.15 and AMD DRM 3.42. The 24.08 Mesa branch is selected instead of the newer 25.08 branch that delivered Mesa 26.2.x on the affected machine.

The historical application bundle is built by GitHub Actions from the original Flathub packaging source. Its proprietary Spotify payload is not hosted in this repository: Flatpak obtains it from the original Snapcraft URL and checks the SHA-256 recorded in the historical Flathub recipe.

## Install or repair the pinned build

From the project directory:

```bash
bash ./scripts/install_legacy_spotify.sh
```

The script:

1. Uses the `FLATPAK_USER_DIR` selected by `.setup-dir` (Goinfre by default).
2. Installs Freedesktop 24.08 and the Mesa 24.08 GL extension into that user installation.
3. Downloads the release bundle and its checksum over HTTPS.
4. Verifies the bundle checksum before installing it.
5. Verifies the Spotify version and runtime after installation.
6. Masks the Spotify app and Mesa extension against automatic replacement.

No administrator privileges are requested. The system-wide Spotify installation is not changed.

If the release asset is not available yet, check the project's GitHub Actions page for the **Build historical Spotify 1.2.52.442 Flatpak** workflow. The installer must not fall back to the current Flathub Spotify version.

## Verify the selected installation

Always select the project-owned user installation:

```bash
export FLATPAK_USER_DIR="/goinfre/$USER/spotify-spicetify/flatpak"
flatpak info --user com.spotify.Client
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
