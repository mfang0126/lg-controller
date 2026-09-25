# LG Volume Router — macOS menu-bar app: Mac volume keys control your LG webOS TV

[中文说明](README.zh-CN.md)

A native macOS menu-bar app and companion CLI that route macOS media-volume keys to your LG webOS TV whenever that TV is the Mac's current sound output — so the volume keys always adjust what you are actually hearing.

> **Release status — v0.2.0:** public **source-only** release under the [MIT License](LICENSE). Build it locally from the tagged source. No prebuilt App or CLI binary is published, and the project is not Developer ID signed or notarized. v0.2.0 changes routing from focused-display matching to sound-output matching; existing users re-select the TV's sound output device once in **Configure…** (see [Changelog](CHANGELOG.md)).

## Features

- **Output-aware routing:** routes volume up, volume down, or mute to the configured LG webOS TV only while macOS's default sound output is that TV's audio device — the volume keys always control what you are hearing. AirPlay outputs always pass through because macOS can already adjust them.
- **Manual override:** three modes — **When the TV is the sound output** (default), **Always to the TV**, and **Never to the TV**.
- **Preserves normal macOS behavior:** when routing is off, Accessibility is unavailable, the sound output is not the configured TV, or no TV is configured, the original media key is left for macOS.
- **Local webOS control:** uses webOS Secure Simple Access Protocol (SSAP) over local WSS for pairing, status reads, volume control, and mute.
- **Minimal menu bar app:** one routing switch, a configuration window, and a menu-bar icon that reflects last-known TV audio state.
- **Safe connection test:** **Test connection** performs an audio-state read only. It never changes volume or mute.
- **Standalone CLI:** supports `pair`, `status`, `up`, `down`, and `mute` without macOS Accessibility permission.
- **Shared local pairing:** the App and CLI use the same configuration domain and macOS Keychain service, so they can share an approved TV pairing.

This project is not affiliated with, endorsed by, or sponsored by LG Electronics.

## Requirements

- macOS 13 or later.
- An LG webOS TV reachable from the Mac on the local network.
- Xcode command-line tools to compile the source.
- macOS Accessibility permission **only** for the menu-bar app to observe and conditionally intercept global media keys. The CLI does not require Accessibility.

## Build from source

Clone the repository and build both components:

```sh
git clone https://github.com/mfang0126/lg-webos-volume-router.git
cd lg-webos-volume-router
make all
```

The source build intentionally disables code signing:

```text
build/Build/Products/Release/LGVolumeRouter.app
build/lg-volume
```

Launch the App after building:

```sh
make run-app
```

The resulting App is a local build, not a notarized consumer distribution. macOS may require you to make your own trust decision before opening it. Do not redistribute that build as an official signed release.

## Configure the App

1. Launch `LGVolumeRouter.app`.
2. Select the menu-bar icon, then choose **Configure…**.
3. Enter the TV's local hostname or IP address.
4. Choose the TV's sound output device (for example the HDMI device named after the TV) and the routing mode.
5. Choose **Test connection**. If the TV requests pairing, approve it on the TV. The test reads TV audio state; it does not change audio.
6. Turn on **Volume routing** in the menu.
7. When macOS asks, grant Accessibility permission to the App. macOS owns this approval; the App cannot grant, bypass, or automate it.

The App stores non-secret endpoint/audio-device settings in local UserDefaults and stores the webOS client key in the macOS Keychain. Never commit, export, or share either as project files.

### Menu-bar icon

The icon represents the **last known TV audio state**, not whether routing is enabled:

| TV state | Icon |
|---|---|
| Not yet read | `speaker` |
| Muted | `speaker.slash` |
| Low volume | `speaker.wave.1` |
| Medium volume | `speaker.wave.2` |
| High volume | `speaker.wave.3` |

Routing enablement is shown by the **Volume routing** switch and the icon tooltip. Audio state refreshes at startup, when the menu opens, after **Test connection**, and after a successful routed command. It does not poll continuously or subscribe to TV-remote changes.

## CLI

Build only the CLI if needed:

```sh
make cli
```

Usage:

```text
./build/lg-volume <pair|status|up|down|mute> [--host <address>] [--port <port>]
```

### Pair and control

`pair` deletes the saved client key for the selected host, then requests a new approval on the TV:

```sh
./build/lg-volume pair --host <TV_ADDRESS>
```

After approval, control the same TV:

```sh
./build/lg-volume status --host <TV_ADDRESS>
./build/lg-volume up --host <TV_ADDRESS>
./build/lg-volume down --host <TV_ADDRESS>
./build/lg-volume mute --host <TV_ADDRESS>
```

The CLI reads the same saved endpoint as the App when the App has already been configured. `--host` and `--port` are one-command overrides; they do **not** save configuration. For a CLI-only workflow without App configuration, provide `--host` for every command. In the App, **Advanced settings** exposes `wss` (the default) and `ws`; the CLI supports **WSS only**, so keep the App on `wss` when you want both surfaces to share an endpoint.

`status` reads and prints the TV volume/mute state. `up` and `down` change volume. `mute` first reads the current mute state and then toggles it. Pairing keys remain in the local Keychain and are never printed.

## Security and privacy boundaries

- Control traffic is sent only to the local TV endpoint you configure.
- LG TVs commonly use a local self-signed WSS certificate. The source contains a narrowly scoped exception for the configured TV socket; it is not a general HTTPS/WSS certificate bypass.
- The project has no account system, cloud service, telemetry, analytics, or remote-control relay.
- Never expose a TV address, pairing key, Keychain export, signing certificate, provisioning profile, API key, or local build output in an issue, commit, screenshot, or release asset.
- The source release does not include a Developer ID certificate, notarization credentials, or prebuilt binaries.

See [Security and privacy](docs/SECURITY.md) for the full model.

## Documentation

- [中文 README](README.zh-CN.md)
- [Architecture](docs/ARCHITECTURE.md) — components, command flow, and invariants.
- [Security and privacy](docs/SECURITY.md) — Keychain, pairing, WSS trust scope, and permission boundaries.
- [Release guide](docs/RELEASE.md) — source-only policy and public-release safeguards.
- [Contributing](CONTRIBUTING.md) — development and validation expectations.
- [Changelog](CHANGELOG.md) — release history.

## License

[MIT](LICENSE) © 2026 `mfang0126`.
