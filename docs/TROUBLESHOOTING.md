# Troubleshooting log and compatibility notes

This file records issues reproduced during development on the 42 campus Ubuntu machine. It is intended to turn one-off fixes into repeatable checks. It is not a guarantee that the same workaround is correct on every Linux machine.

## Known machine profile

Observed on 2026-11-21:

- Ubuntu 22.04.2 LTS, x86_64
- Linux kernel: `5.15.0-203-generic`
- glibc: `2.35`
- AMD GPU present
- AMD DRM warning from the newer Spotify launch: DRM interface `3.42`; the bundled Mesa warned that it expects `3.54` or newer
- Home filesystem was low on free space; `/goinfre` had approximately 48 GiB free
- No sudo privileges

Do not update the system glibc by replacing `/lib`, `/lib64`, or the system dynamic loader. A private glibc is not a fix for a kernel DRM compatibility warning.

## Reproduced Spotify comparison

| Installation | Spotify version | Freedesktop runtime | Mesa extension | Observed result |
|---|---|---|---|---|
| Existing system Flatpak | 1.2.52.442.g01893f92 | 24.08 | 25.2.6 | User reported that the interface displayed smoothly |
| Goinfre user Flatpak | 1.2.95.453.g0eeebbed | 25.08 | 26.2.5 / 26.2.7 updates observed | User reported a visually glitched interface; AMD DRM compatibility warning appeared |

This is strong evidence that the newer graphics stack is involved, but it is not a perfectly isolated test: the Spotify application builds differ too. Keep the known-working system installation unchanged until the user-owned compatibility installation is confirmed.

The system installation's known-good Flatpak commit observed on this machine:

`d5724652e6dbee2d912d4da426b55d6d16364c405d4f271ca2f04855a7046366`

It uses Freedesktop runtime 24.08. This commit is a machine-observed baseline, not a promise that Flathub will retain it forever.

## Important command lessons

### Always select the custom user installation

The user installation is stored under the project setup directory. Commands that inspect or run it must receive the same `FLATPAK_USER_DIR`:

```bash
export FLATPAK_USER_DIR="/goinfre/$USER/spotify-spicetify/flatpak"
flatpak info --user com.spotify.Client
flatpak run --user com.spotify.Client
```

Without this environment variable, Flatpak may inspect the default user installation and report that Spotify is not installed.

The project's `launch.sh` already reads `.setup-dir` and configures this environment for launch.

### flatpak kill does not accept --user

This is invalid:

```bash
flatpak kill --user com.spotify.Client
```

Use `flatpak ps` to identify the running instance, then pass its instance ID to `flatpak kill INSTANCE_ID`. This matters if both system and user copies are running because both share the same application ID.

### flatpak-builder is not the same as flatpak build-bundle

- `flatpak-builder` is a separate build tool used to build an application from a manifest.
- `flatpak build-bundle` is included in the Flatpak command-line tool and exports an already-existing ref from a local OSTree repository.
- A bundle does not include its runtime dependencies. The runtime must be available separately.

Do not install `flatpak-builder` just to export an already-installed system Spotify package.

### The Spotify profile still uses home storage

Setting `FLATPAK_USER_DIR` moves the user Flatpak application/runtime repository, not the app's sandbox profile. Spotify's profile remains under:

`~/.var/app/com.spotify.Client`

The system and user Flatpak copies share this per-app profile directory. Do not run both copies simultaneously while testing, logging in, or applying Spicetify. Do not put the prefs file, credentials, session tokens, or cache into Git.

## Interpreting launch messages

- `Failed to load module canberra-gtk-module`: GTK module warning; not by itself proof of a Spotify failure.
- Ayatana app-indicator deprecation: warning, not by itself proof of broken playback or rendering.
- Protobuf parse warnings: observed in the older working system Spotify build; visual playback still worked for the user. Record them, but do not assume they caused the graphical issue.
- `amdgpu: DRM version is 3.42.0 ... compatible with 3.54.0 ...`: graphics compatibility warning and the leading clue for the Goinfre build's rendering issue.
- `SSL error: unable to get local issuer certificate`: certificate-chain/trust problem. Do not disable TLS verification or use `curl -k`. Investigate the campus CA/trust store separately.
- `stack smashing detected`: process memory-corruption abort. Treat as a real crash, not a harmless warning.

The `--disable-gpu` launch-flag test did not resolve the user's visual problem, so it should not be treated as the final fix.

## Recovery strategy under investigation

1. Preserve the working system Spotify installation.
2. Check whether the exact known-good app commit is still available from the user's Flathub remote using `flatpak remote-info --user --commit=COMMIT flathub com.spotify.Client`.
3. If the remote no longer serves the commit, test whether the user can export the already-installed system app from `/var/lib/flatpak/repo` with `flatpak build-bundle`. Read access to the repository config alone does not prove all OSTree objects are readable.
4. Install the app into the Goinfre-backed user installation only after the selected recovery source is verified. The app's manifest must continue to declare runtime 24.08.
5. Verify the deployed runtime and graphics extension from inside the user app sandbox, then confirm the app directory is writable and run Spicetify backup/apply.
6. Do not remove the existing user app, system app, profile, or Mesa runtimes until the recovered copy has been tested successfully.

## Safe diagnostic command

Run:

```bash
chmod +x scripts/*.sh
./scripts/diagnose.sh
```

The report prints versions, commits, runtimes, graphics driver choices, and storage usage. It deliberately does not print the contents of Spotify prefs or other private session data.
