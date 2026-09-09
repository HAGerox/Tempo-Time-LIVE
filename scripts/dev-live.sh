#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x .build/live-foreground-venv/bin/python || ! -x .build/live-review-venv/bin/python ]]; then
  bash scripts/prepare-runtime.sh
fi
python3 scripts/prepare-models.py
mkdir -p .build/live-dev
cat > .build/live-dev/tempo-live <<EOF
#!/bin/bash
exec "$PWD/.build/live-foreground-venv/bin/python" "$PWD/audio_runtime/coordinator.py"
EOF
chmod +x .build/live-dev/tempo-live
export TEMPO_BEATNET_WORKER="$PWD/.build/live-dev/tempo-live"
npm exec -- tauri dev
