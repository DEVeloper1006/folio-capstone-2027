"""Evaluate the pix2tex (LaTeX-OCR) baseline on a folder of handwritten math PNGs.

Ground truth is read from, in order of precedence:
  1. ``labels`` in the config: a JSON file ({"img.png": "latex", ...}) or a
     TSV file (``filename<TAB>latex`` per line).
  2. A sidecar ``<stem>.tex`` or ``<stem>.txt`` next to each image.

Images with no ground truth are still predicted and saved, but are excluded
from the metrics.

Usage (from repo root):
    python experiments/hme-recognition/eval_pix2tex.py [--config PATH] [--image-dir DIR] [--limit N]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from shared.eval.metrics import compute_all, normalized_edit_distance  # noqa: E402
from shared.utils.latex_normalize import normalize_latex  # noqa: E402
from shared.utils.rasterize import load_grayscale, preprocess  # noqa: E402

EXPERIMENT_NAME = "hme-recognition"
DEFAULT_CONFIG = Path(__file__).resolve().parent / "configs" / "default.yaml"
IMAGE_EXTS = {".png", ".jpg", ".jpeg"}


@dataclass
class Sample:
    image: str
    prediction: str
    reference: str | None
    exact_match: bool | None
    edit_distance: float | None
    latency_ms: float
    error: str | None = None


def resolve_path(p: str | Path) -> Path:
    """Resolve config paths relative to the repo root."""
    path = Path(p)
    return path if path.is_absolute() else REPO_ROOT / path


def load_config(path: Path, overrides: dict[str, Any]) -> dict[str, Any]:
    with open(path) as f:
        cfg: dict[str, Any] = yaml.safe_load(f) or {}
    cfg.update({k: v for k, v in overrides.items() if v is not None})
    return cfg


def load_labels(labels_path: Path | None) -> dict[str, str]:
    """Load a filename -> LaTeX mapping from a JSON or TSV file."""
    if labels_path is None:
        return {}
    if not labels_path.exists():
        raise FileNotFoundError(f"labels file not found: {labels_path}")
    if labels_path.suffix == ".json":
        with open(labels_path) as f:
            return {str(k): str(v) for k, v in json.load(f).items()}
    labels: dict[str, str] = {}
    with open(labels_path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or "\t" not in line:
                continue
            name, latex = line.split("\t", 1)
            labels[name.strip()] = latex
    return labels


def find_reference(image: Path, labels: dict[str, str]) -> str | None:
    for key in (image.name, image.stem):
        if key in labels:
            return labels[key]
    for ext in (".tex", ".txt"):
        sidecar = image.with_suffix(ext)
        if sidecar.exists():
            return sidecar.read_text().strip()
    return None


def list_images(image_dir: Path, limit: int | None) -> list[Path]:
    if not image_dir.is_dir():
        raise FileNotFoundError(f"image_dir does not exist: {image_dir}")
    images = sorted(p for p in image_dir.iterdir() if p.suffix.lower() in IMAGE_EXTS)
    return images[:limit] if limit else images


def load_model() -> Any:
    try:
        from pix2tex.cli import LatexOCR
    except ImportError as e:
        raise SystemExit("pix2tex is not installed. Run `make setup` first.") from e
    return LatexOCR()


def run(cfg: dict[str, Any]) -> dict[str, Any]:
    image_dir = resolve_path(cfg["image_dir"])
    output_dir = resolve_path(cfg.get("output", f"results/{EXPERIMENT_NAME}/"))
    labels_path = resolve_path(cfg["labels"]) if cfg.get("labels") else None
    use_preprocess = bool(cfg.get("preprocess", False))
    limit = cfg.get("limit")

    images = list_images(image_dir, limit)
    if not images:
        raise SystemExit(f"No images found in {image_dir}")
    labels = load_labels(labels_path)

    print(f"Loading {cfg.get('model', 'pix2tex')}...")
    model = load_model()

    samples: list[Sample] = []
    for i, image_path in enumerate(images, 1):
        img: Image.Image = preprocess(image_path) if use_preprocess else load_grayscale(image_path)
        ref = find_reference(image_path, labels)
        start = time.perf_counter()
        error = None
        try:
            pred = str(model(img.convert("RGB")))
        except Exception as e:  # keep going; one bad image shouldn't kill the run
            pred, error = "", f"{type(e).__name__}: {e}"
        latency_ms = (time.perf_counter() - start) * 1000
        samples.append(
            Sample(
                image=image_path.name,
                prediction=pred,
                reference=ref,
                exact_match=None if ref is None else normalize_latex(pred) == normalize_latex(ref),
                edit_distance=None if ref is None else normalized_edit_distance(pred, ref),
                latency_ms=latency_ms,
                error=error,
            )
        )
        print(f"  [{i}/{len(images)}] {image_path.name} ({latency_ms:.0f} ms)", flush=True)

    labeled = [s for s in samples if s.reference is not None]
    metrics = (
        compute_all([s.prediction for s in labeled], [s.reference for s in labeled])  # type: ignore[misc]
        if labeled
        else {}
    )
    latencies = [s.latency_ms for s in samples]

    result = {
        "experiment": EXPERIMENT_NAME,
        "model": cfg.get("model", "pix2tex"),
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "config": cfg,
        "counts": {
            "images": len(samples),
            "labeled": len(labeled),
            "unlabeled": len(samples) - len(labeled),
            "errors": sum(s.error is not None for s in samples),
        },
        "metrics": metrics,
        "latency_ms": {
            "mean": sum(latencies) / len(latencies),
            "p50": sorted(latencies)[len(latencies) // 2],
            "max": max(latencies),
        },
        "samples": [asdict(s) for s in samples],
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"pix2tex_{datetime.now():%Y%m%d_%H%M%S}.json"
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2)

    print_table(result)
    print(f"\nWrote {out_path.relative_to(REPO_ROOT) if out_path.is_relative_to(REPO_ROOT) else out_path}")
    return result


def print_table(result: dict[str, Any]) -> None:
    counts, metrics, lat = result["counts"], result["metrics"], result["latency_ms"]
    rows: list[tuple[str, str]] = [
        ("Images", str(counts["images"])),
        ("Labeled", str(counts["labeled"])),
        ("Errors", str(counts["errors"])),
    ]
    if metrics:
        rows += [
            ("ExpRate", f"{metrics['exp_rate'] * 100:.2f}%"),
            ("ExpRate <=1", f"{metrics['exp_rate_le1'] * 100:.2f}%"),
            ("ExpRate <=2", f"{metrics['exp_rate_le2'] * 100:.2f}%"),
            ("BLEU-4", f"{metrics['bleu'] * 100:.2f}"),
            ("Norm. edit dist", f"{metrics['edit_distance']:.4f}"),
        ]
    else:
        rows.append(("Metrics", "n/a (no labels found)"))
    rows += [("Latency mean", f"{lat['mean']:.0f} ms"), ("Latency p50", f"{lat['p50']:.0f} ms")]

    width = max(len(k) for k, _ in rows)
    print(f"\n{result['model']} on {result['experiment']}")
    print("-" * (width + 16))
    for k, v in rows:
        print(f"{k:<{width}}  {v:>12}")
    print("-" * (width + 16))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--image-dir", dest="image_dir")
    parser.add_argument("--labels")
    parser.add_argument("--output")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--preprocess", action="store_true", default=None)
    args = parser.parse_args()

    overrides = {k: v for k, v in vars(args).items() if k != "config"}
    run(load_config(args.config, overrides))


if __name__ == "__main__":
    main()
