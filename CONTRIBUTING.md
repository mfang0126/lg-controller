# Contributing

## Development setup

```sh
make all
make run-app
```

The repository has no third-party runtime dependencies. Keep generated output under ignored build directories; do not add `build/`, `build-*`, `bin/`, `.hermes/`, Keychain exports, or local settings to commits.

## Change boundaries

- Keep app and CLI configuration compatible through `ProductConfiguration.swift`.
- Treat `WebOSProvider`, `KeychainStore`, TLS challenge handling, and SSAP registration permissions as security-sensitive.
- Do not broaden the local TLS exception to arbitrary hosts or certificates.
- Do not add any path that logs, prints, or serializes webOS client keys.
- Preserve the distinction between routing state and TV audio-state icon semantics.
- Do not bypass or automate macOS Accessibility/TCC permission approval.

## Validation

This feature-only MVP currently has no automated test suite. Before proposing a change:

```sh
make clean
make all
git diff --check
```

Then perform the relevant manual check on a non-production TV:

- app launches and config window opens;
- **Test connection** reads status without changing audio;
- `lg-volume pair|status|up|down|mute` behaves as documented;
- the app only routes a media key for the configured focused display;
- the menu-bar icon follows the documented audio-state mapping.

Never paste a real TV address or pairing key into an issue, commit, screenshot, or pull-request description.

## Documentation

Update the relevant public document when behavior changes:

- user behavior: `README.md`;
- component/invariant: `docs/ARCHITECTURE.md`;
- permission, TLS, storage, or pairing: `docs/SECURITY.md`;
- build/distribution process: `docs/RELEASE.md`;
- shipped behavior: `CHANGELOG.md`.
