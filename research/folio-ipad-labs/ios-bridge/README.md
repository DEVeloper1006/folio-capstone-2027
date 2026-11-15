# ios-bridge

**Status: Placeholder**

Swift-side glue between PencilKit ink capture in the Folio iPad app and on-device models exported from `experiments/` (CoreML via `shared/export/coreml_export.py`).

- `InkCapture.swift` — turn a `PKDrawing` into model input (rasterized image or stroke sequence), matching the preprocessing in `shared/utils/rasterize.py`.
- `ModelRunner.swift` — load a compiled CoreML model, run inference, decode output to LaTeX.

Preprocessing must stay in sync with the Python side, or on-device accuracy will not match eval numbers.
