"""Loader for the MathWriting 2024 dataset (InkML online handwriting + LaTeX labels).

Layout under ``data/mathwriting-2024/``: one ``<sample_id>.inkml`` per sample in
``train/``, ``valid/``, ``test/``, ``synthetic/`` and ``symbols/``. Each file has
``<annotation type=...>`` entries (``label``, ``normalizedLabel``, ``sampleId``,
``splitTagOriginal``, ``inkCreationMethod``) and ``<trace>`` elements of
comma-separated ``"x y t"`` points (y points down, t in ms). There are no
pre-rendered images; use ``MathWritingSample.render()``.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import numpy as np
from PIL import Image

from shared.utils.rasterize import render_ink

DEFAULT_ROOT = Path(__file__).resolve().parents[2] / "data" / "mathwriting-2024"
SPLITS = ("train", "valid", "test", "synthetic", "symbols")
_NS = {"ink": "http://www.w3.org/2003/InkML"}

LabelField = Literal["normalized", "raw"]


@dataclass
class MathWritingSample:
    sample_id: str
    split: str
    strokes: list[np.ndarray]  # each (N, 3): x, y, t
    label: str
    normalized_label: str  # falls back to ``label`` when absent (e.g. symbols/)
    creation_method: str | None

    def render(self, **kwargs: Any) -> Image.Image:
        """Rasterize the ink; kwargs go to ``shared.utils.rasterize.render_ink``."""
        return render_ink(self.strokes, **kwargs)

    def get_label(self, field: LabelField = "normalized") -> str:
        return self.normalized_label if field == "normalized" else self.label


def _parse_trace(text: str) -> np.ndarray:
    points = [p.split() for p in text.strip().split(",") if p.strip()]
    return np.array(points, dtype=np.float64).reshape(len(points), -1)


def parse_inkml(path: str | Path) -> MathWritingSample:
    """Parse one MathWriting InkML file."""
    path = Path(path)
    root = ET.parse(path).getroot()
    ann = {a.get("type"): (a.text or "") for a in root.findall("ink:annotation", _NS)}
    strokes = [_parse_trace(t.text or "") for t in root.findall("ink:trace", _NS)]
    label = ann.get("label", "")
    return MathWritingSample(
        sample_id=ann.get("sampleId", path.stem),
        split=ann.get("splitTagOriginal", path.parent.name),
        strokes=[s for s in strokes if len(s)],
        label=label,
        normalized_label=ann.get("normalizedLabel") or label,
        creation_method=ann.get("inkCreationMethod"),
    )


def list_files(split: str, root: str | Path = DEFAULT_ROOT) -> list[Path]:
    """Sorted list of InkML files in a split."""
    split_dir = Path(root) / split
    if not split_dir.is_dir():
        raise FileNotFoundError(
            f"MathWriting split not found: {split_dir} "
            f"(expected one of {SPLITS}; is the archive fully extracted?)"
        )
    return sorted(split_dir.glob("*.inkml"))


def load_split(
    split: str = "valid",
    root: str | Path = DEFAULT_ROOT,
    limit: int | None = None,
) -> list[MathWritingSample]:
    """Parse the first ``limit`` samples (sorted by id) of a split."""
    files = list_files(split, root)
    if limit is not None:
        files = files[:limit]
    return [parse_inkml(f) for f in files]


def load_pairs(
    split: str = "valid",
    root: str | Path = DEFAULT_ROOT,
    limit: int | None = None,
    render: bool = True,
    label_field: LabelField = "normalized",
    **render_kwargs: Any,
) -> list[tuple[Image.Image | list[np.ndarray], str]]:
    """Return ``(image_or_ink, latex_label)`` pairs.

    With ``render=True`` the first element is a grayscale PIL image, otherwise
    the raw list of strokes.
    """
    return [
        (s.render(**render_kwargs) if render else s.strokes, s.get_label(label_field))
        for s in load_split(split, root, limit)
    ]
