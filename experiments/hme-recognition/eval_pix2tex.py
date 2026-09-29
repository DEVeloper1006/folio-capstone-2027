"""Evaluate the pix2tex (LaTeX-OCR) baseline on handwritten math.

Two data sources (``dataset`` in the config):

* ``mathwriting`` (default): InkML samples from ``data/mathwriting-2024/<split>/``,
  rendered to images with ``shared/utils/rasterize.render_ink``. Each prediction
  is scored against both ``normalizedLabel`` (primary, the official ground
  truth) and the raw ``label``; the gap shows how much error is LaTeX style
  rather than recognition.
* ``folder``: a folder of PNG/JPGs. Ground truth comes from ``labels`` (JSON
  ``{"img.png": "latex"}`` or TSV ``filename<TAB>latex``) or from a sidecar
  ``<stem>.tex`` / ``<stem>.txt``. Unlabeled images are predicted but excluded
  from metrics.

Data loading, scoring, the table and JSON output live in ``hme_common.py``.

Usage (from repo root):
    python experiments/hme-recognition/eval_pix2tex.py [--config PATH] [--split valid] [--limit N]
    python experiments/hme-recognition/eval_pix2tex.py --dataset folder --image-dir DIR [--labels FILE]
"""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
from typing import Any

from hme_common import CONFIG_DIR, DATASETS, EXPERIMENT_NAME, dataset_tag, evaluate, load_config, load_items, resolve_path

DEFAULT_CONFIG = CONFIG_DIR / "default.yaml"


def load_model() -> Any:
    try:
        from pix2tex.cli import LatexOCR
    except ImportError as e:
        raise SystemExit("pix2tex is not installed. Run `make setup` first.") from e
    return LatexOCR()


def run(cfg: dict[str, Any]) -> dict[str, Any]:
    cfg.setdefault("model", "pix2tex")
    items, label_fields = load_items(cfg)
    output_dir = resolve_path(cfg.get("output", f"results/{EXPERIMENT_NAME}/"))
    out_path = output_dir / f"pix2tex_{dataset_tag(cfg)}_{datetime.now():%Y%m%d_%H%M%S}.json"

    print(f"Loading {cfg['model']}...")
    model = load_model()
    return evaluate(model, cfg, items, label_fields, out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--dataset", choices=sorted(DATASETS))
    parser.add_argument("--split", help="MathWriting split (train/valid/test/synthetic/symbols)")
    parser.add_argument("--root", help="MathWriting root directory")
    parser.add_argument("--image-dir", dest="image_dir", help="folder dataset: image directory")
    parser.add_argument("--labels", help="folder dataset: JSON/TSV labels file")
    parser.add_argument("--output")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--preprocess", action="store_true", default=None)
    args = parser.parse_args()

    overrides = {k: v for k, v in vars(args).items() if k != "config"}
    run(load_config(args.config, overrides))


if __name__ == "__main__":
    main()
