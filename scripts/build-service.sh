#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product tempo-service \
  -Xswiftc -file-prefix-map -Xswiftc "$HOME=/build" \
  -Xswiftc -debug-prefix-map -Xswiftc "$HOME=/build" \
  -Xcc "-ffile-prefix-map=$HOME=/build"
TEMPO_TARGET=$(rustc -vV | sed -n 's/^host: //p')
mkdir -p src-tauri/binaries
cp .build/release/tempo-service "src-tauri/binaries/tempo-service-$TEMPO_TARGET"
strip -S "src-tauri/binaries/tempo-service-$TEMPO_TARGET"
codesign --force --options runtime --entitlements assets/TempoTime.entitlements --sign - "src-tauri/binaries/tempo-service-$TEMPO_TARGET"
