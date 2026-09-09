#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Do not put a developer's home directory into the shipped Rust binary.
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME=/build"
npm exec -- tauri build "$@"
