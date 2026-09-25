# Security and privacy

## Scope

LG Controller (formerly LG Volume Router) controls a TV reachable on the user's local network. It does not provide an account system, cloud service, analytics pipeline, telemetry backend, or remote-control relay.

## Data handling

| Data | Storage | Repository policy |
|---|---|---|
| TV host, port, protocol, target audio-device selection, routing preference | Local UserDefaults | Never commit exports or machine state. |
| webOS client key | Host-scoped macOS Keychain item | Never log, print, export, or commit. |
| TV volume/mute readback | In-memory provider cache | Not persisted as a history. |
| macOS Accessibility permission | macOS TCC database | The app cannot grant, bypass, or replace this permission. |

## Pairing

Pairing sends the webOS SSAP registration request and waits for the TV to approve it. The resulting client key is stored through `KeychainStore`; it is not put in `RouterSettings`, source code, release artifacts, command output, or documentation.

`lg-volume pair` is destructive by design: it removes the saved key for the selected host and requests new TV approval. The status/control commands do not remove a key.

## Local TLS behavior

Many LG TVs expose a locally generated TLS certificate for WSS. `WebOSProvider` and the CLI contain a narrowly scoped trust challenge handler so a configured local LG WSS endpoint can connect. This is not a general certificate bypass:

- the challenge is accepted only for the configured WSS host and port;
- it is not applied to arbitrary HTTPS/WSS destinations;
- pairing and control stay on the local network endpoint selected by the user.

Review any change to this logic as security-sensitive.

## macOS permissions

The menu-bar app needs Accessibility permission only to observe and conditionally intercept global media keys. macOS owns that approval. The app cannot automate administrator credentials, Touch ID, TCC database edits, or permission grants.

The CLI has no Accessibility dependency. It can pair, read status, and change the configured TV's audio state with local network access and an approved webOS client key.

## Security boundaries and non-goals

- The project does not attempt to authenticate the user to the TV beyond webOS's local pairing protocol.
- The project does not expose the TV on the internet; users should not port-forward the TV control endpoint.
- A local-network attacker model is not eliminated by the narrow self-signed certificate exception. Treat the trusted LAN as part of the deployment boundary.
- A public binary requires its own signing and notarization review. An unsigned source build is not equivalent to a trusted consumer distribution.

## Reporting a vulnerability

Do not open a public issue containing a TV address, pairing key, Keychain dump, log with credentials, or a reproduction that exposes a private network. Until a security contact is published, report sensitive findings privately to the repository owner through GitHub's private contact mechanism.
