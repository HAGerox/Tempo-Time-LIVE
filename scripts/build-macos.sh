#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-version.py
npm test
npm run test:pulse
npm run runtimes:build
npm run package -- --bundles app -- --locked
python3 scripts/compact-macos-bundle.py 'src-tauri/target/release/bundle/macos/Tempo Time LIVE.app'
python3 scripts/check-macos-bundle.py 'src-tauri/target/release/bundle/macos/Tempo Time LIVE.app'
python3 scripts/test-live-runtime.py 'src-tauri/target/release/bundle/macos/Tempo Time LIVE.app/Contents/Resources/runtime/tempo-live/tempo-live'
mkdir -p dist/dmg-stage
# Keep the familiar local launch path pointing to the Tauri build.
python3 - <<'PY'
from pathlib import Path
import shutil
app = Path('dist/dmg-stage/Tempo Time LIVE.app')
if app.exists(): shutil.rmtree(app)
shutil.copytree('src-tauri/target/release/bundle/macos/Tempo Time LIVE.app', app, symlinks=True)
PY
python3 scripts/package-macos-dmg.py 'dist/dmg-stage/Tempo Time LIVE.app' dist/tempo-time-live-macOS.dmg
