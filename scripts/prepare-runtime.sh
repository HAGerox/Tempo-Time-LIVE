#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv venv --python 3.11 .build/live-foreground-venv --allow-existing
uv pip sync --python .build/live-foreground-venv/bin/python audio_runtime/foreground.lock
uv pip install --python .build/live-foreground-venv/bin/python --no-build-isolation --no-deps madmom==0.16.1
uv venv --python 3.11 .build/live-review-venv --allow-existing
uv pip sync --python .build/live-review-venv/bin/python audio_runtime/review.lock
python3 scripts/prepare-models.py
