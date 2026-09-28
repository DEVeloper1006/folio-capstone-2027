#!/usr/bin/env bash
# Download HME datasets into data/ at the repo root (gitignored).
# Usage: bash shared/data/download.sh [mathwriting|crohme|all]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATA_DIR="$REPO_ROOT/data"
mkdir -p "$DATA_DIR"

download_mathwriting() {
  # TODO: confirm the current MathWriting release URL and pick a subset (full archive is large).
  echo "TODO: download MathWriting into $DATA_DIR/mathwriting"
}

download_crohme() {
  # TODO: CROHME is distributed via TC11 / competition sites; add source URL + checksum.
  echo "TODO: download CROHME into $DATA_DIR/crohme"
}

case "${1:-all}" in
  mathwriting) download_mathwriting ;;
  crohme) download_crohme ;;
  all) download_mathwriting; download_crohme ;;
  *) echo "Unknown dataset: $1" >&2; exit 1 ;;
esac
