# Architecture

## Purpose

LG Volume Router maps a macOS media-key action to the LG webOS TV configured for the display containing the focused macOS window. The macOS app handles focus and Accessibility-sensitive input; the CLI reuses only the local-control and storage layers.

## Components

| Component | Responsibility | Boundary |
|---|---|---|
| `AppDelegate` | Starts the menu-bar controller. | App lifecycle only. |
| `MenuBarController` | Owns menu/configuration UI and maps cached TV state to an SF Symbol. | UI is always updated on the main queue. |
| `VolumeRouter` | Decides whether a media key should be routed and queues a provider command. | Never changes macOS volume itself. |
| `MediaKeyCapture` | Installs the global event tap after macOS Accessibility has been granted. | Required for app media-key capture; absent from CLI. |
| `FocusScreenResolver` | Resolves the focused window into a display identity. | Uses Accessibility geometry, not display names alone. |
| `RouterSettings` | Persists non-secret TV/display configuration. | No pairing key or credential storage. |
| `KeychainStore` | Stores a host-scoped webOS client key. | Keychain only; no repository persistence. |
| `WebOSProvider` | Serializes WSS lifecycle, pairing, reads, and volume/mute commands. | Its state queue is the single owner of session state. |
| `WebOSMessage` | Defines SSAP payloads and tolerant JSON parsing. | Registers audio-read and audio-control permissions. |
| `tools/lg-volume.swift` | Standalone pairing/status/control client. | Does not depend on Accessibility. |

## Command flow

```text
media key
  -> MediaKeyCapture
  -> VolumeRouter
  -> FocusScreenResolver
  -> RouterSettings display match
  -> WebOSProvider serialized WSS command
  -> LG webOS TV
```

The router ignores a key when routing is disabled, macOS Accessibility is unavailable, there is no focused-window/display match, or the matched display has no configured TV. In those cases it does not synthesize or change macOS volume.

## Pairing and storage flow

```text
App or CLI
  -> SSAP register request with audio permissions
  -> TV pairing prompt
  -> client key response
  -> host-scoped macOS Keychain item
```

The App's standard UserDefaults domain and the CLI's explicit persistent domain both use `ProductConfiguration.bundleIdentifier`; `KeychainStore` uses that same value as its service. This keeps their local endpoint configuration and pairing namespace aligned. `pair` intentionally deletes the existing host key first so the user can force a fresh TV approval.

## Provider invariants

1. `WebOSProvider` owns connection and command state on one serial queue.
2. A webOS `PROMPT` is not authorization; no command is sent until a client key is received.
3. The self-signed certificate exception is restricted to the configured local LG WSS host and port, not arbitrary endpoints.
4. Each successful volume/mute action performs one readback before publishing audio state.
5. Audio-state refreshes are event-driven rather than periodic: startup, menu opening, connection test, or a successful routed command.
6. UI handlers dispatch to the main queue and must not mutate provider state directly.

## Status icon semantics

The status item expresses **last known TV audio state**, not routing enablement:

| TV state | Symbol |
|---|---|
| Unknown/not yet read | `speaker` |
| Muted | `speaker.slash` |
| Low volume | `speaker.wave.1` |
| Medium volume | `speaker.wave.2` |
| High volume | `speaker.wave.3` |

Routing enablement is represented only by the `Volume routing` menu item and tooltip. Keeping those concepts separate prevents `speaker.slash` from ambiguously meaning both “muted” and “routing disabled.”
