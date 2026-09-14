# Release guide

## Distribution status

The source tree is buildable as an unsigned macOS app and standalone CLI. It is **not** a Developer ID signed or notarized consumer distribution. Do not describe an unsigned build as signed, notarized, trusted by Gatekeeper, or ready for general download.

## v0.1.0 policy

Version `v0.1.0` is a **source-only** public release under the MIT License. Its GitHub Release may include GitHub's automatically generated source archives for the exact tag, but it must not include an App bundle, CLI executable, dSYM, checksum for an unpublished binary, or any other manually uploaded binary asset.

Users compile the tagged source locally with `make all`. The default build deliberately uses `CODE_SIGNING_ALLOWED=NO`; it is neither a Developer ID signed nor a notarized consumer distribution.

## Local release-candidate build

```sh
make clean
make all
```

Expected outputs:

```text
build/Build/Products/Release/LGVolumeRouter.app
build/lg-volume
```

Inspect the artifacts before packaging:

```sh
plutil -extract CFBundleIdentifier raw \
  build/Build/Products/Release/LGVolumeRouter.app/Contents/Info.plist
file build/lg-volume
codesign -dvv build/Build/Products/Release/LGVolumeRouter.app
```

An unsigned candidate has no Developer Team identifier. That is expected for the repository's default build and is a release-policy fact, not a warning to suppress.

## Mandatory public-source gate

Before `git add`, verify the candidate does not contain local/private/generated material:

```sh
git status --short
git ls-files -co --exclude-standard | sort
```

Confirm that `.gitignore` excludes at least:

- `build/`, `build-*/`, `dist/`, and `bin/`;
- `.hermes/` backups and task artifacts;
- Xcode `xcuserdata/` state;
- `.DS_Store`.

Then search the candidate for private material, including LAN addresses, local signing identities, local absolute paths, client keys, and credentials. Do not rely on a single keyword scan: inspect all staged paths and any release archives.

## Redaction manifest

The following material is never part of a public commit or release archive:

| Category | Required handling |
|---|---|
| TV configuration and pairing keys | Keep in UserDefaults and the macOS Keychain only; never export, log, or stage them. |
| Signing and notarization material | Keep certificates, provisioning profiles, API keys, app-specific passwords, and exported keychains out of the repository and assets. |
| Machine identity | Exclude local absolute paths, per-user Xcode state, automation backups, terminal logs, and Finder metadata. |
| Generated outputs | Rebuild from tagged source; exclude `build/`, `build-*/`, `dist/`, `bin/`, and dSYMs unless an explicitly approved asset is recreated and separately scanned. |
| Retired product identities | Scan source and every asset for old bundle IDs and local signing identities before upload. |

## Packaging policy

For `v0.1.0`, do not upload binary assets. The release notes must say that users build the App and CLI from the exact tagged source using Xcode/macOS.

If a later policy authorizes binary assets, assemble them only from a newly scanned clean Release build—not from the running debug app, `bin/`, or a locally signed bundle. Generate and publish SHA-256 checksums alongside every asset. Include architecture and signing/notarization state in the release notes.

## Remote publication gate

Public repository creation, tag creation, GitHub Release creation, and asset upload are separate external state changes. Immediately before them:

1. confirm the GitHub account, repository owner/name, visibility, and current scopes;
2. inspect the full staged diff and `git diff --check`;
3. independently review the source candidate for scope drift, privacy leaks, build evidence, and release-note accuracy;
4. create the repository with `--public` only after the owner confirms the final target;
5. push the exact tag/commit;
6. read back repository visibility, default branch, tag SHA, release asset names/sizes/checksums, and rendered README.

## Signing and notarization

Developer ID signing and Apple notarization require credentials and an Apple Developer distribution workflow that are intentionally absent from this source repository. Never commit signing certificates, provisioning profiles, notarization credentials, API keys, or exported keychains. When a notarized distribution is later authorized, document its signing identity provenance, CI/host custody, artifact hashes, notarization ticket evidence, and exact tag.
