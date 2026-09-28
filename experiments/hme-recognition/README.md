# hme-recognition

Handwritten math expression (HME) → LaTeX. The first milestone is a **pix2tex (LaTeX-OCR) baseline**: run the off-the-shelf model on handwritten math and measure how far it is from usable for Folio.

## What it does

`eval_pix2tex.py` loads pix2tex, runs it on each sample, scores the predictions, prints a results table, and writes a JSON file (config, metrics, latency, per-sample predictions) to `results/hme-recognition/`.

Data sources (`dataset` in `configs/default.yaml`):

- **`mathwriting`** (default): [MathWriting 2024](https://arxiv.org/abs/2404.10690) InkML samples from `data/mathwriting-2024/<split>/`, loaded with `shared/data/mathwriting.py` and rendered to images with `shared/utils/rasterize.render_ink` (the dataset ships ink only, no images).
- **`folder`**: a folder of PNG/JPGs with labels from a JSON/TSV file or `<stem>.tex` sidecars.

Metrics come from `shared/eval/metrics.py`; LaTeX is normalized with `shared/utils/latex_normalize.py` before comparison.

## How to run

```bash
make setup          # pip install -e .
make eval-hme       # MathWriting test split (7,644 samples)

# quicker runs / other splits
python experiments/hme-recognition/eval_pix2tex.py --split valid --limit 200

# folder of images
python experiments/hme-recognition/eval_pix2tex.py --dataset folder --image-dir DIR --labels labels.tsv
```

Preview a few rendered samples and their labels (sanity check):

```bash
python experiments/hme-recognition/preview_mathwriting.py --split valid --n 3
# -> results/hme-recognition/sample_previews/<sample_id>.png
```

### Which label? (MathWriting)

Each ink has two labels, and 47% of valid samples differ between them:

- `normalizedLabel` (**primary**) is the official ground truth, in one canonical style: `\binom{j}{m+1}` becomes `(\begin{matrix}j\\ m+1\end{matrix})`, `\bar` becomes `\overline`, `\over` becomes `\frac`, and `\varepsilon` becomes `\epsilon`. Use it to compare with published numbers.
- `label` (**raw**) is the LaTeX as originally written. It's closer to pix2tex's own style, so it's fairer to pix2tex.

Every run scores against both. The rows marked `[raw]` in the table show the second set, and the gap shows how much of the error is LaTeX style rather than recognition.

## Metrics

| Metric | Meaning |
|--------|---------|
| ExpRate | % exact match after normalization (token level) |
| ExpRate ≤1 / ≤2 | % within 1 / 2 token edits |
| BLEU-4 | corpus BLEU over LaTeX tokens |
| Norm. edit dist | mean token edit distance / max length (lower is better) |

## Expected results

pix2tex is trained on **rendered** LaTeX, not handwriting, so expect it to do poorly here. Rough guide (unverified, to be replaced with measured numbers):

- ExpRate: low, likely well under 20% on MathWriting test
- BLEU-4: moderate, since partial structure is often recovered
- Normalized edit distance: high
- `[raw]` scores somewhat above `normalized`

The point of this baseline is a floor for handwriting-specific models trained on MathWriting.

## Data license

MathWriting is **CC BY-NC-SA 4.0** (non-commercial), and its Wikipedia-derived LaTeX is CC BY-SA. Check this before shipping anything trained on it in Folio.
