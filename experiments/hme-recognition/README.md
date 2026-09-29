# hme-recognition

Handwritten math expression (HME) → LaTeX for the Folio iPad workspace. Both models are run on the same MathWriting samples and scored with the same metrics.

| Model | Status | Eval script |
|-------|--------|-------------|
| pix2tex (LaTeX-OCR) | **Ruled out**: 0% ExpRate on handwriting | `eval_pix2tex.py` |
| Uni-MuMER (Qwen3-VL-2B) | **Active baseline**: 41% ExpRate (46.5% vs raw label) | `eval_unimumer.py` |

## Results: MathWriting valid, first 200 samples

Same 200 samples (sorted by ID), same rendering (height 128, stroke width 3), scored against `normalizedLabel`, with `[raw]` = the original `label`.

| Metric | pix2tex | Uni-MuMER-Qwen3-VL-2B |
|--------|---------|-----------------------|
| ExpRate | 0.00% | **41.00%** |
| ExpRate ≤1 | 0.00% | 59.00% |
| ExpRate ≤2 | 0.00% | 68.50% |
| BLEU-4 | 2.61 / 2.91 (two runs) | 68.94 |
| Norm. edit dist ↓ | 0.831 / 0.820 | 0.157 |
| ExpRate [raw] | 0.00% | **46.50%** (≤1: 65.5%, ≤2: 77.0%, BLEU 82.27) |
| Latency mean (M-series Mac) | ~410 ms (CPU) | ~1.0 s (MPS, bf16, greedy) |

**pix2tex:** it recovered the rough structure (`\frac`, `\int`, `\overline`) but read handwritten glyphs as unrelated font symbols (`\mathcal`, `\setminus`, ...). It was trained only on typeset LaTeX, so the domain gap is too large. pix2tex samples during decoding, so BLEU varies slightly between runs. Only one render setting was tried; a render-size sweep was not run.

**Uni-MuMER:** a real baseline, with 0 errors across 200 samples. Its published result on MathWriting **test**, using their own rendering and label cleanup, is 51.4% exact / 67.5% ≤1 / 76.8% ≤2 (`uni-mumer/example_data/MathWriting/results/mathwriting_test_results.txt`). Our raw-label numbers (46.5 / 65.5 / 77.0) fall in the same range, so the pipeline matches theirs. The ~72% in their Model Zoo is an average over all benchmarks; CROHME is easier than MathWriting.

Where the 118 misses against `normalizedLabel` come from:
- **18 are LaTeX style only** and exact against the raw label: `\binom` vs a matrix, `pmatrix`/`bmatrix` vs `(\begin{matrix})`. Uni-MuMER applies its **own** label normalization, not MathWriting's `normalizedLabel`, so the `[raw]` column is the fairer measure of recognition.
- **More style mismatches hide among the remaining 100**: `\bar` vs `\overline`, `\cup\limits` vs `\bigcup`, `\int\limits`. Adding these to `shared/utils/latex_normalize.py` would raise the scores without changing the model.
- **Real misreads are mostly near-misses.** 41 of the 100 are one token off, typically look-alike glyphs: τ→r, τ→t, o→θ, ν→V.

## Data

- **MathWriting 2024** is at `data/mathwriting-2024/`. It's loaded by `shared/data/mathwriting.py` and rendered from ink to images by `shared/utils/rasterize.render_ink`, because the dataset ships only ink, no images.
- **`folder` mode** in `eval_pix2tex.py` accepts any PNG folder, with labels from JSON/TSV or `<stem>.tex` sidecar files.

Shared eval plumbing lives in `hme_common.py`: data loading, scoring against both labels, the results table, and JSON output. Each eval script only supplies a `predict(image) -> str`.

### Which label?

Each ink has two labels, and 47% of valid samples differ between them:

- `normalizedLabel` (**primary**) is the official ground truth, in one canonical style: `\binom` becomes a matrix, `\bar` becomes `\overline`, `\over` becomes `\frac`, and `\varepsilon` becomes `\epsilon`. Neither pix2tex nor Uni-MuMER writes in this style.
- `label` (**raw**) is the LaTeX as originally written.

Every run scores against both. The gap shows how much of the error is LaTeX style rather than recognition.

## How to run

```bash
python3.11 -m venv .venv && source .venv/bin/activate
make setup                   # base deps incl. pix2tex

# pix2tex
python experiments/hme-recognition/eval_pix2tex.py --split valid --limit 200

# Uni-MuMER: one-time setup, then eval (defaults: valid, 200 samples)
make setup-unimumer          # clone repo (gitignored), install extras, download ~4.3 GB weights
make eval-unimumer           # -> results/hme-recognition/unimumer_baseline.json
python experiments/hme-recognition/eval_unimumer.py --limit 3      # quick smoke test
python experiments/hme-recognition/eval_unimumer.py --split test --limit 0 --output-file results/hme-recognition/unimumer_test.json   # full test split (7,644)
```

Preview rendered samples and their labels:

```bash
python experiments/hme-recognition/preview_mathwriting.py --split valid --n 3
```

## Uni-MuMER setup details

- **Paper/code:** https://github.com/BFlameSwift/Uni-MuMER (Apache-2.0), pinned at commit `85732e0`.
- **Weights:** [`phxember/Uni-MuMER-Qwen3-VL-2B`](https://huggingface.co/phxember/Uni-MuMER-Qwen3-VL-2B), 2.1B params, one 4.26 GB bf16 `model.safetensors`. They download to the Hugging Face cache (`~/.cache/huggingface`, or `$HF_HOME`), never into the repo.
- **Manual steps**, if `make setup-unimumer` fails:
  1. `GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/BFlameSwift/Uni-MuMER experiments/hme-recognition/uni-mumer`
  2. `pip install -e ".[unimumer]"` (needs `transformers>=4.57` for Qwen3-VL)
  3. `hf download phxember/Uni-MuMER-Qwen3-VL-2B`. The download stalled repeatedly on 2026-09-29, both over Xet and over plain HTTP (`HF_HUB_DISABLE_XET=1`), and a restarted `hf` begins a new partial file from zero. What worked:
     - Resume the partial file directly: `curl -L -C - -o <cache>/blobs/<sha>.<id>.incomplete https://huggingface.co/phxember/Uni-MuMER-Qwen3-VL-2B/resolve/main/model.safetensors`.
     - Check `shasum -a 256` equals the blob name (`e9e0bd18…c4fe125d4`).
     - Rename it to `blobs/<sha>` and symlink `snapshots/<rev>/model.safetensors -> ../../blobs/<sha>`.
- **How our inference differs from theirs:**
  - Their `scripts/vllm_infer.py` uses vLLM, which needs CUDA, so it doesn't run on Apple Silicon. `eval_unimumer.py` reproduces it with Hugging Face `transformers` instead. It uses the same system prompt, the same user prompt (copied verbatim from their data, including the literal `<image>` tag), the ChatML template, and whitespace-stripped output.
  - Decoding is **greedy** for reproducibility. Theirs samples at temperature 0.2 and top_p 0.8; set `--temperature 0.2` to match.
  - They render MathWriting images with their own pipeline. We use `render_ink`, so absolute numbers can differ from their paper.
- **Training data:** training used MathWriting `train` and `symbols` only, per `train/Uni-MuMER-Qwen3-VL-2B.yaml`, so the `valid` and `test` splits are uncontaminated.
- **Device:** it runs on MPS (Apple GPU) in bf16 by default; use `--device cpu --dtype float32` as a fallback.

## Metrics

| Metric | Meaning |
|--------|---------|
| ExpRate | % exact match after normalization (token level) |
| ExpRate ≤1 / ≤2 | % within 1 / 2 token edits |
| BLEU-4 | corpus BLEU over LaTeX tokens |
| Norm. edit dist | mean token edit distance / max length (lower is better) |

## Data license

MathWriting is **CC BY-NC-SA 4.0** (non-commercial), and its Wikipedia-derived LaTeX is CC BY-SA. Uni-MuMER's code and weights are Apache-2.0, but the model was trained on MathWriting, among other data. Check both before shipping in Folio.
