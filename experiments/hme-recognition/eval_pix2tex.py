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

Usage (from repo root):
    python experiments/hme-recognition/eval_pix2tex.py [--config PATH] [--split valid] [--limit N]
    python experiments/hme-recognition/eval_pix2tex.py --dataset folder --image-dir DIR [--labels FILE]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from shared.data.mathwriting import load_split  # noqa: E402
from shared.eval.metrics import compute_all, normalized_edit_distance, token_edit_distance  # noqa: E402
from shared.utils.rasterize import crop_to_ink, load_grayscale, resize_keep_aspect  # noqa: E402

EXPERIMENT_NAME = "hme-recognition"
DEFAULT_CONFIG = Path(__file__).resolve().parent / "configs" / "default.yaml"
IMAGE_EXTS = {".png", ".jpg", ".jpeg"}


@dataclass
class Item:
    """One thing to evaluate: a lazily loaded image plus references per label field."""

    sample_id: str
    load_image: Callable[[], Image.Image]
    refs: dict[str, str | None]


def resolve_path(p: str | Path) -> Path:
    """Resolve config paths relative to the repo root."""
    path = Path(p)
    return path if path.is_absolute() else REPO_ROOT / path


def load_config(path: Path, overrides: dict[str, Any]) -> dict[str, Any]:
    with open(path) as f:
        cfg: dict[str, Any] = yaml.safe_load(f) or {}
    cfg.update({k: v for k, v in overrides.items() if v is not None})
    return cfg


# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------


def mathwriting_items(cfg: dict[str, Any]) -> tuple[list[Item], list[str]]:
    root = resolve_path(cfg.get("root", "data/mathwriting-2024"))
    render_kwargs: dict[str, Any] = cfg.get("render") or {}
    samples = load_split(cfg.get("split", "test"), root, cfg.get("limit"))
    items = [
        Item(
            sample_id=s.sample_id,
            load_image=lambda s=s: s.render(**render_kwargs),
            refs={"normalized": s.normalized_label, "raw": s.label},
        )
        for s in samples
    ]
    return items, ["normalized", "raw"]


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


def folder_items(cfg: dict[str, Any]) -> tuple[list[Item], list[str]]:
    image_dir = resolve_path(cfg["image_dir"])
    if not image_dir.is_dir():
        raise FileNotFoundError(f"image_dir does not exist: {image_dir}")
    images = sorted(p for p in image_dir.iterdir() if p.suffix.lower() in IMAGE_EXTS)
    if cfg.get("limit"):
        images = images[: cfg["limit"]]
    labels = load_labels(resolve_path(cfg["labels"]) if cfg.get("labels") else None)
    items = [
        Item(
            sample_id=p.name,
            load_image=lambda p=p: load_grayscale(p),
            refs={"label": find_reference(p, labels)},
        )
        for p in images
    ]
    return items, ["label"]


DATASETS: dict[str, Callable[[dict[str, Any]], tuple[list[Item], list[str]]]] = {
    "mathwriting": mathwriting_items,
    "folder": folder_items,
}


# ---------------------------------------------------------------------------
# Eval
# ---------------------------------------------------------------------------


def load_model() -> Any:
    try:
        from pix2tex.cli import LatexOCR
    except ImportError as e:
        raise SystemExit("pix2tex is not installed. Run `make setup` first.") from e
    return LatexOCR()


def run(cfg: dict[str, Any]) -> dict[str, Any]:
    dataset = cfg.get("dataset", "mathwriting")
    if dataset not in DATASETS:
        raise SystemExit(f"Unknown dataset {dataset!r}; expected one of {sorted(DATASETS)}")
    output_dir = resolve_path(cfg.get("output", f"results/{EXPERIMENT_NAME}/"))
    use_preprocess = bool(cfg.get("preprocess", False))

    items, label_fields = DATASETS[dataset](cfg)
    if not items:
        raise SystemExit(f"No samples found for dataset={dataset!r}")
    primary = label_fields[0]

    print(f"Loading {cfg.get('model', 'pix2tex')}...")
    model = load_model()

    samples: list[dict[str, Any]] = []
    for i, item in enumerate(items, 1):
        img = item.load_image()
        if use_preprocess:
            img = resize_keep_aspect(crop_to_ink(img), 256, 1024)
        start = time.perf_counter()
        error = None
        try:
            pred = str(model(img.convert("RGB")))
        except Exception as e:  # keep going; one bad image shouldn't kill the run
            pred, error = "", f"{type(e).__name__}: {e}"
        latency_ms = (time.perf_counter() - start) * 1000
        samples.append(
            {
                "sample_id": item.sample_id,
                "prediction": pred,
                "references": item.refs,
                "exact_match": {
                    f: None if r is None else token_edit_distance(pred, r) == 0
                    for f, r in item.refs.items()
                },
                "edit_distance": {
                    f: None if r is None else normalized_edit_distance(pred, r) for f, r in item.refs.items()
                },
                "latency_ms": latency_ms,
                "error": error,
            }
        )
        print(f"  [{i}/{len(items)}] {item.sample_id} ({latency_ms:.0f} ms)", flush=True)

    metrics: dict[str, dict[str, float]] = {}
    for field in label_fields:
        labeled = [s for s in samples if s["references"][field] is not None]
        if labeled:
            metrics[field] = compute_all(
                [s["prediction"] for s in labeled], [s["references"][field] for s in labeled]
            )
    latencies = [s["latency_ms"] for s in samples]
    n_labeled = sum(s["references"][primary] is not None for s in samples)

    result = {
        "experiment": EXPERIMENT_NAME,
        "model": cfg.get("model", "pix2tex"),
        "dataset": dataset,
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "config": cfg,
        "counts": {
            "images": len(samples),
            "labeled": n_labeled,
            "unlabeled": len(samples) - n_labeled,
            "errors": sum(s["error"] is not None for s in samples),
        },
        "primary": primary,
        "metrics": metrics,
        "latency_ms": {
            "mean": sum(latencies) / len(latencies),
            "p50": sorted(latencies)[len(latencies) // 2],
            "max": max(latencies),
        },
        "samples": samples,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    tag = f"{dataset}-{cfg.get('split', 'test')}" if dataset == "mathwriting" else dataset
    out_path = output_dir / f"pix2tex_{tag}_{datetime.now():%Y%m%d_%H%M%S}.json"
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2, default=str)

    print_table(result)
    print(f"\nWrote {out_path.relative_to(REPO_ROOT) if out_path.is_relative_to(REPO_ROOT) else out_path}")
    return result


def _metric_rows(m: dict[str, float], suffix: str = "") -> list[tuple[str, str]]:
    return [
        (f"ExpRate{suffix}", f"{m['exp_rate'] * 100:.2f}%"),
        (f"ExpRate <=1{suffix}", f"{m['exp_rate_le1'] * 100:.2f}%"),
        (f"ExpRate <=2{suffix}", f"{m['exp_rate_le2'] * 100:.2f}%"),
        (f"BLEU-4{suffix}", f"{m['bleu'] * 100:.2f}"),
        (f"Norm. edit dist{suffix}", f"{m['edit_distance']:.4f}"),
    ]


def print_table(result: dict[str, Any]) -> None:
    counts, metrics, lat = result["counts"], result["metrics"], result["latency_ms"]
    primary = result["primary"]
    rows: list[tuple[str, str]] = [
        ("Images", str(counts["images"])),
        ("Labeled", str(counts["labeled"])),
        ("Errors", str(counts["errors"])),
    ]
    if primary in metrics:
        rows += _metric_rows(metrics[primary])
    else:
        rows.append(("Metrics", "n/a (no labels found)"))
    for field, m in metrics.items():
        if field != primary:
            rows += _metric_rows(m, f" [{field}]")
    rows += [("Latency mean", f"{lat['mean']:.0f} ms"), ("Latency p50", f"{lat['p50']:.0f} ms")]

    width = max(len(k) for k, _ in rows)
    title = f"{result['model']} on {result['dataset']}"
    if result["dataset"] == "mathwriting":
        title += f"/{result['config'].get('split')} (primary: {primary}Label)"
    print(f"\n{title}")
    print("-" * (width + 16))
    for k, v in rows:
        print(f"{k:<{width}}  {v:>12}")
    print("-" * (width + 16))


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
