---
name: utility-screenshots
description: Capture or refresh real desktop-app screenshots for a utility product page or release.
---

Use the actual current desktop app, not a web preview with invented window chrome. Use the available screenshot/computer-use tooling and its instructions; never imply a capture succeeded if access is unavailable.

- Run representative, non-sensitive input through the app. Capture its main task and a useful working/result state, normally two images. Wait for the UI and any progress indicators to agree.
- Keep real macOS traffic lights and natural window proportions. Use a compact, consistent logical window size and Retina capture where available, at least twice the intended display dimensions when possible. No demo banners, fabricated controls or upscaled low-resolution images.
- Save original PNGs and web-delivery WebPs in `assets/screenshots/`. Preserve aspect ratio; inspect the WebP at its intended display size for sharp text, cropping and compression artefacts.
- A screenshot must support the adjacent website claim. Refresh images after visible app changes; use the current icon.
- Verify the result visually before reporting it ready. State which app build was captured and any limitation.
