#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/prepare-runtime.sh
for live_kind in foreground review; do
  ".build/live-$live_kind-venv/bin/python" scripts/runtime-notices.py "$live_kind"
done
PYTHONPATH="$PWD/audio_runtime/compat" .build/live-foreground-venv/bin/pyinstaller \
  --noconfirm --clean --onedir --name tempo-live --distpath .build/live-runtime \
  --workpath .build/foreground-freeze --specpath .build \
  --paths audio_runtime --paths audio_runtime/vendor --collect-submodules madmom \
  --add-data "$PWD/.build/live-models/beatnet-plus-af.pt:models" \
  --add-data "$PWD/.build/runtime-notices/foreground:licenses" \
  --exclude-module tkinter --exclude-module IPython --exclude-module pytest \
  audio_runtime/coordinator.py
.build/live-review-venv/bin/pyinstaller \
  --noconfirm --clean --onedir --name tempo-review --distpath .build/live-runtime \
  --workpath .build/review-freeze --specpath .build \
  --paths audio_runtime --collect-submodules beat_this \
  --add-data "$PWD/.build/live-models/beat-this-final0.ckpt:models" \
  --add-data "$PWD/.build/runtime-notices/review:licenses" \
  --exclude-module tkinter --exclude-module IPython --exclude-module pytest \
  audio_runtime/review.py

# Cython build debug records can contain the builder's home/cache directories.
# Strip those records and restore each library's ad-hoc signature.
python3 - <<'PYSTRIP'
from pathlib import Path
import subprocess
for library in Path('.build/live-runtime/tempo-live/_internal/madmom').rglob('*.so'):
    subprocess.run(['strip', '-S', str(library)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(library)], check=True)
PYSTRIP
