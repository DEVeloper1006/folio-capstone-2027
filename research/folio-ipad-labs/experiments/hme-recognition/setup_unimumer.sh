#!/usr/bin/env bash
# Set up Uni-MuMER for eval_unimumer.py:
#   1. clone the Uni-MuMER repo (gitignored) at a pinned commit, for reference
#   2. install the `unimumer` optional deps
#   3. download phxember/Uni-MuMER-Qwen3-VL-2B (~4.5 GB) into the Hugging Face
#      cache (~/.cache/huggingface, or $HF_HOME) -- never into the repo.
#
# Usage (from repo root, with .venv active): bash experiments/hme-recognition/setup_unimumer.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLONE_DIR="$REPO_ROOT/experiments/hme-recognition/uni-mumer"
UNIMUMER_URL="https://github.com/BFlameSwift/Uni-MuMER"
UNIMUMER_COMMIT="85732e04f60fcf7b26bcea9234fdb43c90ab1591"
MODEL_ID="phxember/Uni-MuMER-Qwen3-VL-2B"
PYTHON="${PYTHON:-python}"

if [[ ! -d "$CLONE_DIR/.git" ]]; then
  echo "[1/3] Cloning Uni-MuMER into $CLONE_DIR"
  GIT_LFS_SKIP_SMUDGE=1 git clone -q "$UNIMUMER_URL" "$CLONE_DIR"
else
  echo "[1/3] Uni-MuMER already cloned"
fi
git -C "$CLONE_DIR" fetch -q origin "$UNIMUMER_COMMIT" 2>/dev/null || true
git -C "$CLONE_DIR" -c advice.detachedHead=false checkout -q "$UNIMUMER_COMMIT"

echo "[2/3] Installing deps"
"$PYTHON" -m pip install -q -e "$REPO_ROOT[unimumer]"

echo "[3/3] Downloading $MODEL_ID (~4.5 GB) to the Hugging Face cache"
if command -v hf >/dev/null; then
  hf download "$MODEL_ID"
else
  huggingface-cli download "$MODEL_ID"
fi

echo "Done. Run: python experiments/hme-recognition/eval_unimumer.py"
