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

## Tempo Time LIVE Retina capture

The approved method captures the actual AppKit view at its Retina backing scale.
Computer-use screenshots may return only 720 × 470 pixels and alter the rendered
colours; use them for UI inspection, not the published image assets.

1. Copy the current packaged app into an ignored `.build/capture/` directory,
   preserving runtime symlinks. Keep the distributed app and DMG untouched.
2. Compile the adjacent `capture-view.m` using `clang -dynamiclib -fobjc-arc
   -framework Cocoa`, writing the dylib into the capture directory. Ad-hoc sign
   the private app copy without hardened-runtime options so it can load the
   capture helper. This private copy must never be shipped.
3. Close other instances. Launch the copy with `DYLD_INSERT_LIBRARIES` pointing
   to the dylib and `TEMPO_CAPTURE_REQUEST` pointing to a request file in that
   directory. The helper only captures the app's own view; it does not inject
   readings, alter controls or synthesize window chrome.
4. Use the real UI with representative audio and manual keyboard taps. Keep a
   720 × 470 point window on a Retina display. Once the state agrees, write the
   absolute destination PNG path to the request file. The helper consumes it
   and logs the captured dimensions.
5. Require 1440 × 940 PNGs, then convert to lossless WebP while retaining any ICC
   profile. Do not upscale smaller captures. Inspect the results at native and
   intended website sizes; retain originals and set the site's intrinsic image
   dimensions to 1440 × 940. Use new asset filenames when replacing a cached
   lower-resolution version.
6. Quit the private capture copy and stop test playback after capturing.
