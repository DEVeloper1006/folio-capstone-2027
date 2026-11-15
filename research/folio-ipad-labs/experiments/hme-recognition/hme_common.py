"""Shared eval plumbing for hme-recognition model evals (pix2tex, Uni-MuMER, ...).

Each eval script supplies a ``predict(PIL.Image) -> str`` function; this module
handles data loading, scoring against every label field, the results table and
the JSON output, so all models are compared on identical samples and metrics.
"""

from __future__ import annotations

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
CONFIG_DIR = Path(__file__).resolve().parent / "configs"
IMAGE_EXTS = {".png", ".jpg", ".jpeg"}

Predictor = Callable[[Image.Image], str]


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


def display_path(p: Path) -> Path:
    return p.relative_to(REPO_ROOT) if p.is_relative_to(REPO_ROOT) else p


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
    samples = load_split(cfg.get("split", "test"), root, cfg.get("limit") or None)  # 0/null = all
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


def load_items(cfg: dict[str, Any]) -> tuple[list[Item], list[str]]:
    dataset = cfg.get("dataset", "mathwriting")
    if dataset not in DATASETS:
        raise SystemExit(f"Unknown dataset {dataset!r}; expected one of {sorted(DATASETS)}")
    items, label_fields = DATASETS[dataset](cfg)
    if not items:
        raise SystemExit(f"No samples found for dataset={dataset!r}")
    return items, label_fields


def dataset_tag(cfg: dict[str, Any]) -> str:
    dataset = cfg.get("dataset", "mathwriting")
    return f"{dataset}-{cfg.get('split', 'test')}" if dataset == "mathwriting" else dataset


# ---------------------------------------------------------------------------
# Eval
# ---------------------------------------------------------------------------


def evaluate(
    predict: Predictor,
    cfg: dict[str, Any],
    items: list[Item],
    label_fields: list[str],
    out_path: Path,
) -> dict[str, Any]:
    """Run ``predict`` on every item, score it, print the table and write JSON."""
    use_preprocess = bool(cfg.get("preprocess", False))
    primary = label_fields[0]

    samples: list[dict[str, Any]] = []
    for i, item in enumerate(items, 1):
        img = item.load_image()
        if use_preprocess:
            img = resize_keep_aspect(crop_to_ink(img), 256, 1024)
        start = time.perf_counter()
        error = None
        try:
            pred = str(predict(img.convert("RGB"))).strip()
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
        "model": cfg.get("model", "unknown"),
        "dataset": cfg.get("dataset", "mathwriting"),
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

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2, default=str)

    print_table(result)
    print(f"\nWrote {display_path(out_path)}")
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
