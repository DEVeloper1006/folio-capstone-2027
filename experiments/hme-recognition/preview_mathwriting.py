"""Render a few MathWriting samples to PNG and print their labels (sanity check).

Usage (from repo root):
    python experiments/hme-recognition/preview_mathwriting.py [--split valid] [--n 3]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from shared.data.mathwriting import DEFAULT_ROOT, load_split  # noqa: E402
from shared.utils.rasterize import save_png  # noqa: E402

DEFAULT_OUT = REPO_ROOT / "results" / "hme-recognition" / "sample_previews"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--split", default="valid")
    parser.add_argument("--n", type=int, default=3)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--height", type=int, default=128)
    args = parser.parse_args()

    for s in load_split(args.split, args.root, args.n):
        img = s.render(height=args.height)
        path = save_png(img, args.out / f"{s.sample_id}.png")
        print(f"{s.sample_id}  ({len(s.strokes)} strokes, {img.width}x{img.height})")
        print(f"  label:      {s.label}")
        print(f"  normalized: {s.normalized_label}")
        print(f"  -> {path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path}")


if __name__ == "__main__":
    main()
