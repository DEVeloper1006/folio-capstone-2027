"""Export trained PyTorch models to CoreML for on-device inference in ios-bridge/.

Outputs go to results/<experiment>/ (weights are gitignored) — never to tracked paths.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any


def export_to_coreml(
    model: Any,
    example_input: Any,
    out_path: Path,
    compute_units: str = "ALL",
) -> Path:
    """Trace a torch model and convert it to an .mlpackage."""
    # TODO: add coremltools as an optional dependency (e.g. [project.optional-dependencies] export).
    # TODO: torch.jit.trace(model.eval(), example_input).
    # TODO: coremltools.convert(traced, inputs=[ct.ImageType(...)], compute_units=...).
    # TODO: handle encoder/decoder split for autoregressive models (pix2tex-style).
    # TODO: optional FP16 / palettization for size.
    raise NotImplementedError


def validate_export(torch_model: Any, mlmodel_path: Path, example_input: Any, atol: float = 1e-3) -> bool:
    """Check CoreML output matches PyTorch within tolerance."""
    # TODO: run both and compare (requires macOS for CoreML prediction).
    raise NotImplementedError
