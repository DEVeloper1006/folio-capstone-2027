# hme-recognition handoff

This covers everything needed to pick up the handwritten-math-recognition work: what exists, what the results are, how to set up from a fresh clone, and what's left to do, with enough detail to start without asking.

Status as of **2026-09-29**, at commit `e348da9` (the Uni-MuMER baseline). Nothing in `experiments/hme-recognition/` or `shared/` has changed since.

---

## 1. The goal

Folio is an iPad math workspace. The user writes math with Apple Pencil, and we need to turn that ink into LaTeX. This experiment picks the recognition model:

1. Get a strong baseline on a real handwriting benchmark. **(Done.)**
2. Understand the remaining errors and fix the easy ones. **(Next.)**
3. Work out whether the model can run on-device (CoreML) or needs a server. **(Open.)**

This repo is only the ML experimentation layer, not the app. Code that works eventually gets exported (CoreML) and wired up through `ios-bridge/`.

---

## 2. What you can't see (gitignored), and how to get it

Several things exist only on Dev's machine. You have to re-create them; nothing is missing from the code itself.

| Missing on your side | What it is | How to get it |
|---|---|---|
| `data/mathwriting-2024/` | The dataset, about 650k InkML files | Download it (§4.2) |
| `.venv/` | The Python environment | Create it (§4.1) |
| `experiments/hme-recognition/uni-mumer/` | Clone of the Uni-MuMER repo (reference only; our code doesn't import it) | `make setup-unimumer` (§4.3) |
| `~/.cache/huggingface/.../Uni-MuMER-Qwen3-VL-2B` | Model weights, 4.26 GB | `make setup-unimumer` (§4.3) |
| `results/**/*.json` | Eval outputs, including every per-sample prediction | Re-run the evals (§5). All the numbers are also copied into §3 below. |
| `results/hme-recognition/sample_previews/*.png` | 3 rendered sample images | `preview_mathwriting.py` (§5) |
| `.reports/` | Dev's session logs | Not needed; the useful parts are in this file |
| `CLAUDE.md`, `AGENTS.md` | Dev's AI-agent instructions | Not needed; the conventions that matter are in §8 |

---

## 3. Results so far

**Setup for both runs:**
- Data: MathWriting 2024, `valid` split, the first 200 samples sorted by sample ID. This is deterministic, so you'll get the same 200.
- Rendering: ink drawn at height 128 px, stroke width 3.
- Scoring: against both labels (see §3.1).
- Hardware: Apple Silicon Mac.

| Metric | pix2tex | **Uni-MuMER-Qwen3-VL-2B** |
|---|---|---|
| ExpRate (exact match) | 0.00% | **41.00%** |
| ExpRate ≤1 token error | 0.00% | 59.00% |
| ExpRate ≤2 token errors | 0.00% | 68.50% |
| BLEU-4 | 2.61 | 68.94 |
| Normalized edit distance (lower is better) | 0.831 | 0.157 |
| ExpRate **[raw label]** | 0.00% | **46.50%** |
| ExpRate ≤1 / ≤2 [raw] | 0 / 0% | 65.50 / 77.00% |
| BLEU-4 [raw] | 2.67 | 82.27 |
| Norm. edit dist [raw] | 0.837 | 0.123 |
| Latency per image | ~410 ms (CPU) | ~1.0 s (MPS GPU, bf16) |

### 3.1 The two labels

Every MathWriting sample has two ground-truth strings, and **47% of validation samples differ between them**:

- **`normalizedLabel`** is the official ground truth, in one canonical style. It rewrites things:
  - `\binom{4}{2}` → `(\begin{matrix}4\\ 2\end{matrix})`
  - `\bar{f}` → `\overline{f}`
  - `\varepsilon` → `\epsilon`
  - `l \over g` → `\frac{l}{g}`
  - `bmatrix` → `[\begin{matrix}…]`
  - and it adds braces everywhere.
- **`label`** (called "raw" in our code) is the LaTeX as a human originally wrote it.

Our evals score against **both** in one pass. `normalized` is the primary row in the table, and rows marked `[raw]` are the second set. The gap between them shows how much error is LaTeX *style* rather than misread handwriting.

### 3.2 pix2tex: ruled out

- It was trained only on typeset (font-rendered) LaTeX.
- On handwriting it gets the layout roughly right (it spots fractions and integrals) but reads handwritten glyphs as random symbols: `\mathcal{T}`, `\setminus`, `\mathbf{\mu}`.
- 0% ExpRate, across two runs.
- It samples during decoding, so BLEU varies between runs (2.61 vs 2.91).
- A render-size sweep was never run, but with BLEU under 3, it isn't worth pursuing.

### 3.3 Uni-MuMER: the current baseline

- **Paper and code:** https://github.com/BFlameSwift/Uni-MuMER (Apache-2.0).
- **Weights:** [`phxember/Uni-MuMER-Qwen3-VL-2B`](https://huggingface.co/phxember/Uni-MuMER-Qwen3-VL-2B), a Qwen3-VL-2B vision-language model fine-tuned on handwritten math. 2.1B parameters.
- **No test contamination.** Per their `train/Uni-MuMER-Qwen3-VL-2B.yaml`, it was trained on MathWriting `train` and `symbols` only, so `valid` and `test` are fair to evaluate on.
- **Our pipeline reproduces theirs.**
  - Their own result on MathWriting **test** (in their repo at `example_data/MathWriting/results/mathwriting_test_results.txt`): **51.4% exact, 67.5% ≤1, 76.8% ≤2**.
  - Ours on valid, raw label: **46.5 / 65.5 / 77.0**. Same range.
  - The ~72% on their Model Zoo page is an average over all their benchmarks. CROHME is easier than MathWriting, so don't compare against 72%.
- **It writes LaTeX in its own style**, not MathWriting's normalized style: `\binom`, `\bar`, `\begin {pmatrix}`, with spaces between tokens. So **`[raw]` is the fairer measure of recognition quality.**

### 3.4 Error analysis (Uni-MuMER, 200 valid samples)

There are 118 misses against `normalizedLabel`:

- **18 are purely style.** They're exact matches against the raw label. Examples:
  ```
  normalized: (\begin{matrix}j\\ m+1\end{matrix})      pred: \binom { j } { m + 1 }
  normalized: V=(\begin{matrix}0&1\\ 1&0\end{matrix}) pred: V = \begin {pmatrix} 0 & 1 \\ 1 & 0 \end {pmatrix}
  normalized: [\begin{matrix}a\\ b\\ c\end{matrix}]    pred: \begin {bmatrix} a \\ b \\ c \end {bmatrix}
  ```
- **100 miss against both labels.** Some of those are still style:
  ```
  raw: pz\overline{z} + gz + \overline{gz} = q          pred: p z \bar { z } + g z + \bar { g z } = q
  raw: Q:=\bigcup_{\sigma\in\sigma(T_{0})}Q_{\sigma}    pred: Q : = \cup \limits _ { \sigma ... }
  ```
- **The rest are genuine misreads, mostly one token off.** 41 of the 100 are exactly 1 token away. Look-alike glyphs dominate:
  ```
  raw: \frac{dP}{d\tau}          pred: \frac { d P } { d r }          (τ → r)
  raw: R=\int_0^\tau X(s) ds     pred: R = \int \limits _ { 0 } ^ { t } X ( s ) d s   (τ → t)
  raw: o_{n}(R)                  pred: \theta _ { n } ( R )           (o → θ)
  raw: \overline{z}=1-i\sqrt{\nu} pred: \bar { z } = 1 - i \sqrt { V } (ν → V)
  ```

---

## 4. Setup from a fresh clone

Tested on an Apple Silicon Mac (macOS, 16 GB RAM). Notes for Linux/NVIDIA are in §4.5.

### 4.1 Python environment

Use **Python 3.11**. 3.14 is too new for pix2tex's pinned dependencies, and 3.10–3.12 should all work.

```bash
cd folio-ipad-labs
conda deactivate 2>/dev/null        # only if your prompt shows (base); otherwise `python` may point at conda
python3.11 -m venv .venv            # .venv/ is gitignored; keep it at the repo root
source .venv/bin/activate
python -m pip install -U pip
make setup                          # = pip install -e .  (torch, pix2tex, Pillow, numpy, nltk, editdistance, pyyaml)
```

Check it:
```bash
which python                        # should end in folio-ipad-labs/.venv/bin/python
python -c "import torch, shared; print(torch.__version__, torch.backends.mps.is_available())"
```

`pip install -e .` is what makes `import shared...` work from every experiment. Don't add `sys.path` hacks elsewhere.

### 4.2 MathWriting dataset (~3.1 GB download)

```bash
mkdir -p data && cd data
curl -L -O https://storage.googleapis.com/mathwriting_data/mathwriting-2024.tgz   # 3,096,141,721 bytes
tar -xzf mathwriting-2024.tgz        # ~650k small files; extraction takes a while
cd ..
ls data/mathwriting-2024             # readme.md symbols/ symbols.jsonl synthetic/ synthetic-bboxes.jsonl test/ train/ valid/
```

- **Expected file counts:** train 229,864 · valid 15,674 · test 7,644 · synthetic 396,014 · symbols 6,423.
- **Wait for extraction to finish before running anything.** Dev hit a half-extracted state where `test/` didn't exist yet.
- **Delete the `.tgz` afterwards** if disk is tight; the loader only reads the extracted folder.
- **Keep `data/` at the repo root.** It's gitignored (`/data/*`), and datasets must never go inside `experiments/`.
- `shared/data/download.sh` is still a TODO stub. Filling it in with the URL above is a good first small PR (§6, task 0).
- **License:** CC BY-NC-SA 4.0 (non-commercial). See §7.

Sanity check that the loader and renderer work:
```bash
python experiments/hme-recognition/preview_mathwriting.py --split valid --n 3
# prints 3 labels, writes results/hme-recognition/sample_previews/<id>.png. Open them; they should look like the labels.
```

The first three valid samples are `00000b332dcd6fe5` (`\binom{j}{m+1}`), `000453d57c3d334d` (`\int_E f(x) \mu(dx)`) and `0005d0be8e507b24` (`\overline{z}=1-i\sqrt{\nu}`).

### 4.3 Uni-MuMER weights and reference clone

```bash
make setup-unimumer
```

That runs `experiments/hme-recognition/setup_unimumer.sh`, which:
1. clones https://github.com/BFlameSwift/Uni-MuMER into `experiments/hme-recognition/uni-mumer/` (gitignored) and checks out the pinned commit `85732e0`;
2. runs `pip install -e ".[unimumer]"`, which adds `transformers>=4.57` (needed for Qwen3-VL), `accelerate` and `huggingface_hub`;
3. runs `hf download phxember/Uni-MuMER-Qwen3-VL-2B`: one 4.26 GB `model.safetensors`, going to `~/.cache/huggingface/` (or `$HF_HOME`), **never into the repo**.

> **Heads up:** this script's steps were run by hand but the script itself hasn't been run end to end. If it breaks, fix it and commit the fix.

**If the weight download stalls.** This happened twice to Dev: once over Xet, once over plain HTTP. A restarted `hf download` starts a *new* partial file from zero, so it loses progress. What worked instead:

```bash
B=~/.cache/huggingface/hub/models--phxember--Uni-MuMER-Qwen3-VL-2B/blobs
ls -la $B | grep incomplete          # find the biggest *.incomplete file
pkill -f "hf download"               # stop the stalled download
curl -L -C - -o "$B/<that-file>.incomplete" \
  https://huggingface.co/phxember/Uni-MuMER-Qwen3-VL-2B/resolve/main/model.safetensors
shasum -a 256 "$B/<that-file>.incomplete"
# must print e9e0bd18f91a3f0f03e89601627eab62105ba87e38464a7b87e1002c4fe125d4
SHA=e9e0bd18f91a3f0f03e89601627eab62105ba87e38464a7b87e1002c4fe125d4
mv "$B/<that-file>.incomplete" "$B/$SHA"
SNAP=$(ls -d $B/../snapshots/*/)
ln -s ../../blobs/$SHA "${SNAP}model.safetensors"
rm -f $B/*.incomplete                # clean up other partial files
python -c "from huggingface_hub import snapshot_download as s; print(s('phxember/Uni-MuMER-Qwen3-VL-2B', local_files_only=True))"
```

After the download, set `HF_HUB_OFFLINE=1` when running evals so nothing touches the network.

### 4.4 Dependency note

pix2tex and Uni-MuMER share one `.venv`. pix2tex pulled in transformers 5.x, which also supports Qwen3-VL, so there's no conflict. If a future dependency bump breaks one of them, the fallback is a second environment (`.venv-unimumer`; add it to `.gitignore`). Don't pin old versions to work around it.

### 4.5 If you're on Linux with an NVIDIA GPU

- Our `eval_unimumer.py` also works on CUDA: `--device auto` picks `cuda` first.
- You can additionally run **their official vLLM pipeline** as a cross-check. `vllm` needs CUDA, which is why Dev couldn't. See their README and `uni-mumer/eval/eval_mathwriting.sh`. Note their `requirements.txt` pins `transformers==4.52.4`, which is too old for Qwen3-VL, so use a separate env for it.
- Expect much faster runs than ~1 s per image.

---

## 5. How to run things

All commands run from the repo root with `.venv` active.

```bash
# Uni-MuMER on the same 200 valid samples (defaults in configs/unimumer.yaml)
HF_HUB_OFFLINE=1 make eval-unimumer
#   -> prints the results table, writes results/hme-recognition/unimumer_baseline.json (overwritten each run)
#   -> ~4 min on an M-series Mac. Prints "Same 200 samples as pix2tex_..." if a pix2tex run exists to compare against.

# quick smoke test on 3 samples, without overwriting the baseline file
python experiments/hme-recognition/eval_unimumer.py --limit 3 --output-file /tmp/smoke.json

# pix2tex on the same 200 (for completeness; ~1.5 min)
python experiments/hme-recognition/eval_pix2tex.py --split valid --limit 200
#   -> results/hme-recognition/pix2tex_mathwriting-valid_<timestamp>.json

# useful flags (eval_unimumer.py)
--split test            # train / valid / test / synthetic / symbols
--limit 0               # 0 = all samples in the split
--temperature 0.2       # match Uni-MuMER's own sampling (default 0 = greedy, reproducible)
--device cpu --dtype float32   # fallback if MPS misbehaves
--preprocess            # crop to ink + downscale before inference
```

**Result JSON shape** (the same for both models; read it when analyzing errors):
```jsonc
{
  "experiment": "hme-recognition", "model": "...", "dataset": "mathwriting",
  "config": { ... },                        // full config used, for reproducibility
  "counts": {"images": 200, "labeled": 200, "unlabeled": 0, "errors": 0},
  "primary": "normalized",
  "metrics": {
    "normalized": {"exp_rate", "exp_rate_le1", "exp_rate_le2", "bleu", "edit_distance", "num_samples"},
    "raw":        { ...same keys... }
  },
  "latency_ms": {"mean", "p50", "max"},
  "samples": [
    {"sample_id": "00000b332dcd6fe5", "prediction": "\\binom { j } { m + 1 }",
     "references": {"normalized": "...", "raw": "..."},
     "exact_match": {"normalized": false, "raw": true},
     "edit_distance": {"normalized": 0.83, "raw": 0.0},
     "latency_ms": 6453.1, "error": null}
  ]
}
```

---

## 6. What's left to do, in priority order

### Task 0 (warm-up, ~15 min): fill in `shared/data/download.sh`

Replace the `download_mathwriting` TODO with the `curl` + `tar` commands from §4.2. Keep the `crohme` TODO; CROHME isn't needed yet. This forces you through the dataset setup anyway.

### Task 1 (highest value, ~half a day): teach the normalizer the style equivalences, then re-score

**Why:** a chunk of the "errors" are just spelling differences in LaTeX. Fixing the *metric* (not the model) gives a truer number and makes later comparisons meaningful.

**Where:** `shared/utils/latex_normalize.py`. Everything goes through `normalize_latex()`: predictions and both labels, for every model. Metrics in `shared/eval/metrics.py` call it before tokenizing.

**What's already handled:**
- `$` delimiters are stripped.
- Spacing commands are dropped: `\,`, `\quad`.
- `\left`, `\right`, `\big*`, `\displaystyle` and **`\limits`** are already dropped.
- Aliases already mapped: `\dfrac`/`\tfrac`→`\frac`, `\le`→`\leq`, `\ge`→`\geq`, `\ne`→`\neq`, `\to`→`\rightarrow`, `\lvert`/`\rvert`/`\vert`→`|`.
- Single-token script braces are unwrapped: `x^{3}`→`x^3`.
- Whitespace doesn't matter at all, because the tokenizer drops it.

**What to add.** Map to the MathWriting normalized form, since that's the official ground truth:

| Model writes | Normalize to | Difficulty |
|---|---|---|
| `\bar{X}` | `\overline{X}` | easy: add `r"\bar": r"\overline"` to `LATEX_ALIASES` |
| `\varepsilon` | `\epsilon` | easy alias |
| `\begin{pmatrix} … \end{pmatrix}` | `(\begin{matrix} … \end{matrix})` | easy regex. **Watch out:** the model emits `\begin {pmatrix}` *with a space*, so match `\\begin\s*\{pmatrix\}` |
| `\begin{bmatrix} … \end{bmatrix}` | `[\begin{matrix} … \end{matrix}]` | same as above |
| `\binom{a}{b}` | `(\begin{matrix}a\\ b\end{matrix})` | **medium**: needs a small brace-matching helper to find the two arguments, because regex can't handle nested braces like `\binom{n+1}{k_{i}}` |
| `{a \over b}` | `\frac{a}{b}` | medium: brace-aware, same helper |
| `\cup` vs `\bigcup`, `\cap` vs `\bigcap`, `\sum` sizes | *judgment call* | Merging them is lossy (`\cup` and `\bigcup` are different operators). Probably leave them separate and just report how often they occur. Ask Dev. |

This direction was checked on 2026-09-29. Across all 15,674 `valid` samples, `normalizedLabel` contains **zero** occurrences of `\bar`, `pmatrix`, `bmatrix`, `\binom`, `\over` or `\varepsilon`. It uses `\overline` (618 samples) and `\begin{matrix}` (1,782 samples) instead. Their `readme.md` in `data/mathwriting-2024/` describes the normalization. Before adding a mapping beyond this table, grep the normalized labels the same way to confirm which form they use.

**Tests.** There's no test suite yet; add `shared/utils/test_latex_normalize.py` (pytest, `pip install pytest`) with at least the tests below. Only `test_existing_behaviour` passes today; the other three are the spec for this task and **will fail until you implement the mappings**.
```python
from shared.utils.latex_normalize import normalize_latex as n

def test_bar_to_overline():   assert n(r"\bar { z }") == n(r"\overline{z}")
def test_pmatrix_spaced():    assert n(r"\begin {pmatrix} 0 & 1 \end {pmatrix}") == n(r"(\begin{matrix}0&1\end{matrix})")
def test_binom_nested():      assert n(r"\binom{n+1}{k_{i}}") == n(r"(\begin{matrix}n+1\\ k_{i}\end{matrix})")
def test_existing_behaviour(): assert n(r"$\dfrac{a}{b} \le x^{2}$") == r"\frac{a}{b} \leq x^2"
```

**Re-score without re-running the model.** Every prediction is saved in the result JSON, so write `experiments/hme-recognition/rescore.py`:
```python
"""Re-compute metrics for a saved results JSON with the current normalizer (no inference)."""
import argparse, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from shared.eval.metrics import compute_all

p = argparse.ArgumentParser(); p.add_argument("results_json", type=Path); args = p.parse_args()
d = json.loads(args.results_json.read_text())
for field in d["metrics"]:
    rows = [s for s in d["samples"] if s["references"].get(field) is not None]
    old, new = d["metrics"][field], compute_all([s["prediction"] for s in rows], [s["references"][field] for s in rows])
    print(f"[{field}] ExpRate {old['exp_rate']*100:.2f}% -> {new['exp_rate']*100:.2f}%   "
          f"<=1 {old['exp_rate_le1']*100:.2f}% -> {new['exp_rate_le1']*100:.2f}%")
```
Run it on `unimumer_baseline.json` (after regenerating it, §5) before and after your normalizer changes. With the normalizer unchanged, it reproduces the saved numbers exactly (41.00% → 41.00%, 46.50% → 46.50% raw), so any change you see comes from your edits.

**Done when:**
- The tests pass.
- The re-scored normalized ExpRate is reported in the README. It should rise noticeably from 41%; at least the 18 style-only misses should flip.
- The pix2tex numbers are re-scored too, and should stay ~0.

### Task 2 (~2.5 h of mostly waiting): full test-split run

For the headline number to compare against their published **51.4%**:
```bash
HF_HUB_OFFLINE=1 nohup python experiments/hme-recognition/eval_unimumer.py \
  --split test --limit 0 --output-file results/hme-recognition/unimumer_test.json > /tmp/unimumer_test.log 2>&1 &
tail -f /tmp/unimumer_test.log
```
- 7,644 samples at ~1 s each is about 2.2 hours on an M-series Mac. Keep the machine awake (`caffeinate -i` in front of the command).
- Do Task 1 first so this number uses the improved normalizer; or just re-score afterwards with `rescore.py`.
- Put the result in the README's results table as a new column.

### Task 3 (exploratory): close the gap to their 51.4%

Things that might explain the ~5-point gap between ours (raw, valid) and theirs (test):

1. **Rendering.** They render MathWriting ink with their own pipeline; we use `shared/utils/rasterize.render_ink` (height 128, stroke width 3, padding 16).
   - Look in `uni-mumer/preprocess/` for how they render.
   - Or sweep settings: height ∈ {64, 96, 128, 192, 256} × stroke width ∈ {2, 3, 4}, on ~100 valid samples each.
   - Render settings live in `configs/unimumer.yaml` under `render:`. Copy the config per setting rather than editing the default.
2. **Sampling.** `--temperature 0.2` matches theirs; greedy (our default) usually scores the same or slightly better.
3. **Split difference.** Valid and test may simply differ in difficulty. Task 2 answers that.

Report what you tried, even if nothing helps. Negative results are useful here.

### Task 4 (research): can this run on the iPad?

This is the question that decides the architecture.
- The model is 2.1B params, 4.26 GB in bf16, ~1 s per image on an M-series Mac GPU. An iPad has less memory to spare.
- Things to try or estimate:
  - CoreML conversion of Qwen3-VL-2B (`shared/export/coreml_export.py` is a TODO stub; note the vision encoder and the autoregressive decoder probably need separate handling).
  - 4-bit or 8-bit quantization and its accuracy cost, measured with our eval.
  - MLX as an alternative on-device path.
  - The fallback: server-side inference.
- `ios-bridge/` holds Swift placeholders (`InkCapture.swift`, `ModelRunner.swift`). **Dev owns `ios-bridge/`; propose changes, don't rewrite it.**
- The deliverable is a short write-up in the README with measured size, latency and accuracy per option.

### Nice-to-haves (lower priority)

- `shared/data/crohme.py` is a stub. CROHME is the other standard handwriting benchmark, and a second benchmark would make results more trustworthy.
- Fine-tuning Uni-MuMER on Folio's own handwriting, once real app data exists.
- The error analysis in §3.4 was done by hand; a script that buckets misses (style-only, ≤1 token, look-alike glyph) would make it repeatable.

---

## 7. Licensing: read before shipping anything

- **MathWriting** is **CC BY-NC-SA 4.0**, so non-commercial use only. Its Wikipedia-derived LaTeX is CC BY-SA.
- **Uni-MuMER** code and weights are Apache-2.0, **but the model was trained on MathWriting** and other datasets.
- Evaluating is fine. Anything that ships in Folio needs a licensing check first. Flag it to Dev; don't decide it alone.

---

## 8. Repo conventions (from Dev's private agent notes, `CLAUDE.md`)

- **Don't push straight to `main` without Dev.** Work on a branch (`git checkout -b hme/normalizer-equivalences`) and open a PR.
- **Never commit model weights**: `.pt`, `.bin`, `.safetensors`, `.onnx`, `.mlmodel`, `.mlpackage`. They're gitignored, but don't `git add -f`.
- **Datasets go in `data/`** at the repo root (gitignored), never inside `experiments/`.
- **Results:** every eval prints metrics to stdout **and** writes JSON to `results/<experiment>/`. The JSON is gitignored, so **copy the numbers that matter into the experiment README.** That's how results get shared.
- **Configs** are YAML files in `experiments/<name>/configs/`.
- **Dependencies** go in `pyproject.toml` (use an optional group like `[unimumer]` for heavy extras). No `requirements.txt`.
- **Python 3.10+, type hints on all function signatures.** Match the surrounding style.
- **Shared code** (loaders, metrics, normalization, rendering) goes in `shared/`. Code used by several scripts *within* hme-recognition goes in `hme_common.py`. **No imports across experiments.**
- **Notebooks** only in `experiments/hme-recognition/notebooks/`, never in production paths.
- **Before claiming something works, run the eval and report the numbers.**

---

## 9. Code map

```
shared/
  data/mathwriting.py      InkML parser + loader. load_split(split, limit), load_pairs(...) -> [(image|strokes, latex)]
  data/crohme.py           STUB
  data/download.sh         STUB (Task 0)
  eval/metrics.py          tokenize_latex, exp_rate(tolerance=0/1/2), bleu (nltk corpus BLEU-4), normalized_edit_distance, compute_all
  utils/latex_normalize.py normalize_latex(): Task 1 lives here
  utils/rasterize.py       render_ink(strokes, height, stroke_width, padding) -> PIL image; crop/resize helpers
  export/coreml_export.py  STUB (Task 4)

experiments/hme-recognition/
  hme_common.py            shared eval plumbing: data sources (mathwriting | folder), evaluate(predict_fn, ...), print_table, JSON writer
  eval_unimumer.py         Uni-MuMER via HF transformers (Qwen3VLForConditionalGeneration), MPS/CUDA/CPU, greedy by default
  eval_pix2tex.py          pix2tex baseline (ruled out; kept for comparison)
  preview_mathwriting.py   render N samples to PNG + print labels (sanity check)
  setup_unimumer.sh        clone Uni-MuMER @85732e0 + install extras + download weights
  configs/default.yaml     pix2tex config (defaults to test split, all samples)
  configs/unimumer.yaml    Uni-MuMER config (valid, 200 samples, render 128/3, greedy)
  README.md                results, setup, how to run. Keep it updated.
  uni-mumer/               (gitignored) reference clone of their repo
```

**Adding a new model** takes about 50 lines: write `eval_<model>.py` that builds a `predict(PIL.Image) -> str` and calls `hme_common.evaluate(predict, cfg, items, label_fields, out_path)`. `eval_unimumer.py` is the template. Data loading, scoring against both labels, the table and the JSON all come for free, so every model gets compared on identical samples.

**Details of how `eval_unimumer.py` differs from Uni-MuMER's own `scripts/vllm_infer.py`:**
- Same system prompt: `You are a helpful assistant.`
- Same user prompt, copied verbatim from their data, **including a literal `<image>` prefix**:
  `<image>I have an image of a handwritten mathematical expression. Please write out the expression of the formula in the image using LaTeX format.`
- Images go straight to the Qwen3-VL processor. Their script uses `qwen-vl-utils`, whose default patch size of 14 is wrong for Qwen3-VL, which uses 16; that's why we skip it.
- Greedy decoding versus their temperature 0.2 / top_p 0.8. The model's own `generation_config.json` defaults to sampling at 0.7, and our script explicitly overrides that.
- `max_new_tokens` is 1024; theirs is 2048. Formulas are short, so this never truncated in our runs.

---

## 10. Gotchas

- **`--limit 0` means all samples**, not zero.
- **`make clean` deletes every results JSON**, including the baselines. Regenerate them if needed.
- **The first Uni-MuMER prediction takes ~6 s** (MPS warm-up); after that it's ~1 s each. Ignore the first sample's latency.
- **Warnings from pix2tex's dependencies are harmless:** albumentations "new version available", pydantic serializer warnings, `torch.jit.script` deprecation. Set `NO_ALBUMENTATIONS_UPDATE=1 PYTHONWARNINGS=ignore` to quiet them.
- **The default pix2tex config runs the full test split** (7,644 samples). Pass `--split valid --limit 200` for the comparable run.
- **The Uni-MuMER clone includes a 27 MB `data.zip`** containing CROHME images and prompts. We don't use it, but the exact prompt text came from `data/CROHME/prompts/*.json` inside it.
- **If a result looks near 0% for Uni-MuMER**, it's a pipeline bug (prompt, image format, or dtype), not the model. Check a few predictions by hand against `sample_previews/` before believing it.

Questions? Ask Dev. For anything touching `ios-bridge/`, licensing, or the `\cup`/`\bigcup` call, check with him before deciding.
