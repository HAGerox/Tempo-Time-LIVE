# Tempo Time LIVE

## Development

Read DESIGN.md and ARCHITECTURE.md.

The desktop app uses the Tauri + React + TypeScript starter from [utility-app-template](https://github.com/HAGerox/utility-app-template), explicitly selected by the user. `npm ci` prepares the frontend; `npm run dev` prepares the pinned model runtimes and opens the app. `npm test` runs the Swift engine and real audio-service integration tests, including the 30-second manual timeout. `bash scripts/build-macos.sh` builds the local app and unsigned DMG. The Swift package contains the audio backend and CLI only; do not restore a SwiftUI interface. A web preview does not verify the Tauri/audio bridge.

Keep the audio callback allocation-free and analysis on its serial worker. Preserve the native detector tests; synthetic PCM is not Dante hardware validation.

## Working rules

- Preserve approved layouts, deliberate deletions and user edits. A small change is not permission for a redesign.
- Keep task logic separate from UI and filesystem/network/process adapters. Use existing libraries for device/protocol behaviour; avoid app-specific allowlists and hardcoded external catalogues.
- Bundle required runtimes, executables and resources. End users must not install Homebrew, Python, Node or development tools. Large downloadable data needs explicit first-use progress and reliable caching.
- Keep long work off the UI thread. Progress must describe the actual operation; cancellation must finish before another job starts.
- Check first launch with fresh app data and required OS permissions, not only a warmed development environment. Verify task outputs against representative expected results; never report success for incomplete or incorrect output.
- Verify the real app with representative input, empty state, failure/cancel/retry and resizing when affected. Build success alone does not prove the UI or output works.
- Sign the macOS app, never the DMG. Use the supplied DMG packager, which verifies the app signature and rejects a signed disk image. This avoids adding a separate Gatekeeper check for the disk image.
- Keep checks focused on changed behaviour. Exercise the packaged app before release; check dependencies without relying on developer PATH.
- Update these instructions only for durable decisions an agent cannot infer from code. Keep README aimed at users with a short developer section.

Project skills in `.agents/skills`: `utility-website` for a product page, `utility-release` for packaging and publishing. For app images, use the shared website skill at `../Stem-Separator-Website/.agents/skills/utility-screenshots/SKILL.md`. Read only the skill relevant to the task. CLAUDE.md imports this file; keep one source of rules.
