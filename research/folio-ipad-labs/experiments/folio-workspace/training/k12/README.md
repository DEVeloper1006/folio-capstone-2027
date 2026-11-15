# Grade 12 recognition experiment

Ontario-inspired mathematical notation through Grade 12, with matrices, integration, and complex numbers marked as extensions. This is not exhaustive curriculum coverage or a mathematics-solving dataset. Diagrams, graphs, proofs, word problems, and full-page layout interpretation are not evaluated.

## Dataset

`artifacts/k12-dataset/` contains 91 families, 3,012 training examples, 364 validation examples, and 364 test examples. Training contains 2,912 original synthetic typeset images and 100 public handwriting samples. Validation and test contain only synthetic images. Exact labels are disjoint across splits; template families and rendering styles are shared. This does not measure generalization to unseen templates or writers.

MathWriting samples retain their source InkML and attribution in the manifests. They carry CC BY-NC-SA 4.0 restrictions, with source expressions under CC BY-SA. The deployed adapter was trained only on original synthetic content. The training script excludes the public handwriting by default. Do not enable noncommercial samples without checking the intended use against their licenses.

Curriculum references:
- https://www.ontario.ca/page/math-curriculum-grades-1-8
- https://www.dcp.edu.gov.on.ca/en/math
- https://www.edu.gov.on.ca/eng/curriculum/secondary/math1112currb.pdf

Handwriting source: https://storage.googleapis.com/mathwriting_data/mathwriting-2024-excerpt.tgz

## Reproduction

Run from the repository root after local OCR setup and `npm install`:

```sh
.venv-local-ocr/bin/python training/k12/build.py --mathwriting /tmp/mathwriting-2024-excerpt
node training/k12/render.mjs
.venv-local-ocr/bin/python training/k12/audit.py
HF_HUB_OFFLINE=1 .venv-local-ocr/bin/python training/k12/train_adapter.py \
  --steps 500 --output artifacts/k12-adapters/new-candidate
HF_HUB_OFFLINE=1 .venv-local-ocr/bin/python training/k12/evaluate.py \
  --split valid --adapter artifacts/k12-adapters/new-candidate \
  --output artifacts/k12-eval/new-candidate-valid
```

Training uses rank-8 attention LoRA, learning rate 0.00005, two accumulated samples per step, and mild training-only image rotation. The deployed run saw 1,000 synthetic examples in 500 optimizer steps. Training never changes the serving worker. Direct `Recognizer()` construction remains the original model for reproducible comparisons; the worker explicitly selects its configured profile.

`compare.py` runs baseline and candidate comparisons and writes progress to `artifacts/k12-eval/final-comparison/status.json`. It never deploys weights. The test split is now observed: retain it as a regression set, not an untouched benchmark for future rounds of tuning.

## Recorded results

| Evaluation | Original first / top 3 | Adapter first / top 3 |
| --- | --- | --- |
| Synthetic test, 364 expressions | 187 / 243 | 350 / 354 |
| Prepared handwriting, 100 images | 67 / 79 | 76 / 88 |
| Native rasterization, 100 stroke samples | 81 / 91 | 82 / 93 |

Two synthetic families regressed on first readings: geometric sequences and limits each fell from 4/4 to 3/4. The adapter does not improve every topic; keep review and alternatives enabled.

Matching removes limited LaTeX formatting differences, not arbitrary mathematical equivalence. These small regression sets do not establish general Grade 12 handwriting accuracy. All native samples remained in one row. The packaged app also passed checks for handwritten arithmetic, a visible typeset 7, review, acceptance, persistence, undo/redo, and stale-request handling. Service checks: 14 passed. Core checks: 10 passed.

The active adapter is pinned by file hashes in `config/local-ocr-grade12.json`. New training runs are not activated automatically. For startup, fallback, and model switching, see `native/README.md`.
