#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMPO_QUEUE_TEST=$(mktemp -d)
trap 'rm -rf "$TEMPO_QUEUE_TEST"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -g -pthread \
  -I Sources/AudioBridge/include Sources/AudioBridge/Queue.c scripts/test-queue.c \
  -o "$TEMPO_QUEUE_TEST/test-queue"
"$TEMPO_QUEUE_TEST/test-queue"
