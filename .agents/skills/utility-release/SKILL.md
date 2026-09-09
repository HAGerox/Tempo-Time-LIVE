---
name: utility-release
description: Build, verify or publish this utility's bundled installers and GitHub releases.
---

Read RELEASE.md and the active workflow. Use only supported platforms and the selected stack.

- Keep app metadata and the `vX.Y.Z` tag consistent. Build the intended commit with lockfiles. Never reuse a published version for different code.
- Exercise the packaged app with real input and verify its output, launch, cancellation and required permissions as relevant. It must not rely on developer-installed runtimes or PATH. Include redistributable dependencies and their required notices.
- Inspect the icon in the actual platform shell; check sizing and padding against platform guidance. Do not fabricate a logo in code as a release shortcut.
- Publish only user installers and genuinely required updater metadata. Keep temporary build outputs in Actions artifacts. Use stable installer filenames for website links.
- Package macOS using `scripts/package-macos-dmg.py`: signed app inside an unsigned DMG. Do not distribute Tauri/Briefcase's separately signed DMG; that previously introduced a second Gatekeeper approval. The script verifies both signature states.
- Ad-hoc signing is not notarization. Do not claim Gatekeeper-free installation. If Developer ID signing or updates are required, implement and verify the platform's supported path; keep signing keys in secrets, never the repository.
- After an authorized release, verify the finished assets and download links, not just that a workflow started. Update website screenshots only when the UI changed.
