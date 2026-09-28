"""Loader for CROHME (InkML handwriting, typically evaluated on 2014/2016/2019 test sets)."""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2] / "data" / "crohme"


@dataclass
class CrohmeSample:
    sample_id: str
    strokes: list[list[tuple[float, float]]]
    latex: str


def parse_inkml(path: Path) -> CrohmeSample:
    """Parse one CROHME InkML file."""
    # TODO: handle the InkML namespace, parse traces, read the "truth" annotation.
    raise NotImplementedError


def iter_year(year: int = 2019, root: Path = DEFAULT_ROOT) -> Iterator[CrohmeSample]:
    """Yield samples from a CROHME test year."""
    # TODO: glob root/str(year)/*.inkml.
    raise NotImplementedError


def export_png_split(year: int, out_dir: Path) -> None:
    """Render each sample to PNG + write labels.tsv for eval_pix2tex.py."""
    # TODO: rasterize strokes (PIL ImageDraw), write <id>.png and labels.tsv.
    raise NotImplementedError
