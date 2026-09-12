# Builds and releases

`bash scripts/build-macos.sh` tests the native engine/service and pulse clock,
prepares pinned runtimes, verifies both model downloads, freezes the workers,
builds the Tauri app, shares byte-identical runtime files with relative symlinks,
restores the app signature and creates the unsigned installer. App staging must
preserve those symlinks; otherwise the installed size expands again.

Outputs: `dist/dmg-stage/Tempo Time LIVE.app` and
`dist/tempo-time-live-macOS.dmg`. The app is ad-hoc signed, not notarized. The DMG
is unsigned. End users need no external Python, Homebrew or developer tools.

## GitHub Actions

`HAGerox/Tempo-Time-LIVE` has the utility template's build/release workflow.
Pushes to `main`, pull requests and manual dispatch run audits, tests and an
Apple Silicon macOS build. Actions are pinned to commits. Build permissions are
read-only; temporary installer artifacts expire after seven days.

A `vX.Y.Z` tag must match app.json, package.json, the Tauri config and Cargo.toml.
A separate release job receives write access and publishes only
`tempo-time-live-macOS.dmg`. Never replace a published version with different code.

Before tagging, exercise the packaged app with representative music and selected
input, verify required permissions and startup, and check reset/quit and pulse
behaviour. Record what was actually tested and any remaining limitations.
Do not equate generated PCM tests with hardware validation or claim notarization.
Source/publication review covers file contents, assets, commit metadata and
required third-party licences; see `docs/PUBLICATION.md`.
