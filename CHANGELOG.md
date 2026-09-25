# Changelog

All notable changes to LG Volume Router are documented here.

## 0.3.0 — 2026-09-25

### Changed

- **Renamed: LG Volume Router → LG Controller (LG 遥控器).** The GitHub repo is now `lg-controller` (old URLs redirect). Bundle id, Keychain service, and pairing are unchanged.
- **Child-simple bilingual UI:** every string is plain English + 中文 side by side. The menu switch is now "Control TV volume / 控制电视音量"; configuration is "Set up TV… / 设置电视…".
- **Two-step setup:** pick your TV from the sound-output list (defaults to the current sound output, with a one-line explanation), then TV address + **Test** side by side.
- **Advanced / 高级设置** now holds everything rarely changed: when-to-control mode (Auto/Always/Never), protocol, port, and **Forget TV pairing**.

### Notes

- Upgrading users: grant Accessibility once more (the rebuilt binary is a new identity), then restart the app — the grant only takes effect after a restart.

## 0.2.0 — 2026-09-25

### Changed (behavior change)

- **Routing is now sound-output based:** media volume keys are routed to the configured LG webOS TV only while macOS's default output device is that TV's audio device — the keys always control what you are actually hearing. The previous focused-display matching was removed along with the display picker. **Upgrading users must re-select the TV's sound output device once in Configure…** (the legacy display setting is not migrated).

### Added

- Routing override with three modes: **When the TV is the sound output** (default), **Always to the TV**, **Never to the TV**.
- Configuration window now lists macOS output devices and shows unavailable configured devices as "not connected" instead of silently re-targeting.
- `make test`: standalone decision-matrix tests for `RoutingPolicy` (15 cases, no Xcode test target needed).
- AirPlay outputs are always passed through to macOS, since macOS can already adjust their volume (avoids double-adjustment).

### Fixed

- Sized the CoreAudio stream-configuration buffer to the reported property size (multi-stream devices).
- Save path re-validates that the selected audio device is still present before persisting.

### Security

- Unchanged: bundle identifier, Keychain service, WSS trust scope, and pairing flow are identical to 0.1.0, so existing TV pairings keep working.

### Known limitations

- App media-key interception requires user-approved macOS Accessibility permission.
- The status icon is refreshed on deliberate events rather than continuous TV-volume subscriptions.
- This is a source-only release: no prebuilt App or CLI binary is published.
- The source build is not Developer ID signed or notarized.

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
