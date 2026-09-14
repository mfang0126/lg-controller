# Changelog

All notable changes to LG Volume Router are documented here.

## 0.1.0 — 2026-09-15

### Added

- Native macOS menu-bar app for display-aware LG webOS volume routing.
- Local SSAP pairing, host-scoped Keychain storage, volume status reads, volume up/down, and mute.
- Standalone `lg-volume` CLI with `pair`, `status`, `up`, `down`, and `mute` commands.
- Read-only connection testing and status-icon mapping for mute/low/medium/high audio states.
- Source build, security, architecture, contribution, and release documentation.
- Complete English and Simplified Chinese README files.
- MIT License.

### Security

- Local self-signed WSS trust handling restricted to the configured LG endpoint.
- Explicit SSAP audio-control and audio-read permissions.
- No client key, private LAN configuration, generated app, local binary, or Hermes backup is included in the public source candidate.

### Known limitations

- App media-key interception requires user-approved macOS Accessibility permission.
- The status icon is refreshed on deliberate events rather than continuous TV-volume subscriptions.
- This is a source-only release: no prebuilt App or CLI binary is published.
- The source build is not Developer ID signed or notarized.
