# hme-recognition

Handwritten math expression (HME) → LaTeX. The first milestone is a **pix2tex (LaTeX-OCR) baseline**: run the off-the-shelf model on handwritten PNGs and measure how far it is from usable for Folio.

## What it does

`eval_pix2tex.py` loads pix2tex, runs it on every PNG/JPG in `image_dir`, compares predictions to ground-truth LaTeX, prints a results table, and writes a JSON file (config, metrics, latency, per-sample predictions) to `results/hme-recognition/`.

Metrics come from `shared/eval/metrics.py`; LaTeX is normalized with `shared/utils/latex_normalize.py` before comparison.

## How to run

```bash
make setup          # pip install -e .
make eval-hme       # uses configs/default.yaml
```

Or with overrides:

```bash
python experiments/hme-recognition/eval_pix2tex.py \
  --image-dir data/crohme/2019/png --labels data/crohme/2019/labels.tsv --limit 200 --preprocess
```

### Ground truth

Either set `labels` in the config (JSON `{"img.png": "latex"}` or TSV `img.png<TAB>latex`), or put a `<stem>.tex` / `<stem>.txt` next to each image. Unlabeled images are still predicted but excluded from metrics.

## Metrics

| Metric | Meaning |
|--------|---------|
| ExpRate | % exact match after normalization (token level) |
| ExpRate ≤1 / ≤2 | % within 1 / 2 token edits |
| BLEU-4 | corpus BLEU over LaTeX tokens |
| Norm. edit dist | mean token edit distance / max length (lower is better) |

## Expected results

pix2tex is trained on **rendered** LaTeX, not handwriting, so expect it to do poorly on handwritten input. As a rough guide (unverified here, to be replaced with measured numbers):

- ExpRate: low, likely well under 20% on CROHME-style data
- BLEU-4: moderate, since partial structure is often recovered
- Normalized edit distance: high

The point of this baseline is a floor for handwriting-specific models (e.g., trained on MathWriting / CROHME).
