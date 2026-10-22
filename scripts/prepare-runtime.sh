#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv venv --python 3.11.17 .build/live-foreground-venv --allow-existing
uv pip sync --python .build/live-foreground-venv/bin/python audio_runtime/foreground.lock
uv pip install --python .build/live-foreground-venv/bin/python --no-build-isolation --no-deps madmom==0.16.1
uv venv --python 3.11.17 .build/live-review-venv --allow-existing
uv pip sync --python .build/live-review-venv/bin/python audio_runtime/review.lock
python3 scripts/patch-madmom.py
for live_kind in foreground review; do
  ".build/live-$live_kind-venv/bin/python" scripts/check-python-security.py
done
python3 scripts/prepare-models.py
