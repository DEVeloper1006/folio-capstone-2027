# On-device TexTeller feasibility checkpoint

Date: 2026-11-04. Target: iPad Air 5 (M1). Desired interaction budget:
**at most 3 seconds from stopping writing to seeing recognition**.

## Decision and scope

**Conversion and Mac correctness baseline: PASS on six synthetic fixtures.**
The existing adapted TexTeller converts into two Core ML ML Program packages,
and both FP32 and FP16 reproduce the original environment's complete greedy
token sequences on the tested inputs. A standalone native iOS probe builds,
signs and runs successfully on the physical M1 iPad Air 5. **Physical-device
fixture parity: PASS; the 3-second interaction target: NOT MET across the test
set.** Warm short inputs take about 1.26–1.90 seconds, but the matrix takes about
4 seconds for inference alone. No full stop-writing → preview measurement has
been performed.

This is an isolated feasibility checkpoint. It does not add offline recognition
to Ink Pad, replace the Mac endpoint, implement `/solve`, or demonstrate real
Apple Pencil accuracy. Synthetic layout fixtures and precomputed normalized
tensors deliberately isolate conversion/runtime correctness from native image
preprocessing and stroke grouping.

## Source and artifacts

Implementation: `experiments/folio-workspace/export/texteller/`:

- `probe.py`: offline reference, LoRA merge, component wrappers, Core ML export,
  numerical comparisons and complete greedy token comparisons.
- `test_probe.py`: five small contract tests, no real model weights loaded.
- `prepare_app.py`: fixture/model staging and standalone Xcode project generation.
- `ProbeApp/ProbeApp.swift`: Swift Core ML loading, bounded token loop, byte-level
  BPE decoding, fixture UI, timing and sampled process footprint.
- `requirements.txt`: isolated conversion environment pins.
- `README.md`: reproduction commands.

Generated artifacts are intentionally ignored at `results/on-device-texteller/`:
`reference.json`, `fixtures/*.png`, `fixtures/*.f32`,
`fixtures/*-reference.npz`, `fixtures/tokenizer-table.json`,
`export-{encoder,decoder}-{fp32,fp16}.json`,
`models/{fp32,fp16}/{Encoder,Decoder}.mlpackage`,
`parity-{fp32,fp16}-mac.json`, `device-ipad-air5-fp16.json`,
`device-console.log`, and `conversion-environment.txt`.
Export manifests contain package file SHA-256 hashes. Reference metadata includes
the adapter hash and original Python package versions.

Existing notebook source and the running recognition environment were preserved.
The pre-change snapshots include the existing uncommitted state in both repos,
not merely their Git HEADs. The main Ink Pad unsigned baseline build passed.

## Exact model and generation contract

| Item | Value |
|---|---|
| Base | `OleehyO/TexTeller` |
| Revision | `7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea` |
| Adapter | Existing `grade12-pilot-500`, `experiments/folio-workspace/models/grade12/` |
| Adapter SHA-256 | `001fdbd1e34661c007a286c04c405d21d56cab71c5006c16e4f56542af4ab6db` |
| Merge | PEFT `merge_and_unload()` before tracing; original adapter left unchanged |
| Encoder | ViT, 12 layers, hidden 768, 12 heads, one channel, 448 pixels, patch 16 |
| Decoder | TrOCR, 12 layers, hidden 1024, 16 heads, FFN 4096, vocabulary 15,000 |
| Base parameter elements | 298,101,248; original checkpoint FP32 |
| Adapter parameter elements | 761,856; merged into base for export |
| Decode | Greedy argmax, BOS 0, EOS 2, maximum 192 new tokens |
| Cache | No KV cache; recomputes the complete prefix each step |
| Core ML target | ML Program, iOS 18 minimum, CPU and GPU enabled |

The original endpoint uses beam search with three beams. This experiment compares
against **greedy** Hugging Face generation with caching enabled, in the original
serving environment. It first proves that the manually split, uncached PyTorch
loop matches that cached greedy reference on all six fixtures. It does **not**
claim parity with production beam-3 outputs or recognition alternatives.

Encoder signature: float32 `pixels[1,1,448,448]` → float32
`encoded[1,785,768]`. Decoder signature: int32 `tokens[1,T]`,
`1 <= T <= 192`, plus encoded features → float32 `logits[1,15000]` for the last
position. FP16 packages use FP16 internal computation/weights with float32
boundary tensors. The greedy loop and detokenizer run in Swift.

Tokenizer handling preserves byte-level BPE rather than joining separately
decoded token strings. Unicode byte fragments are concatenated before UTF-8
decoding; special tokens are removed, common tokenizer cleanup is applied, and
the worker's LaTeX wrapper/percent cleanup is mirrored. Native text decoding
matches all six reference outputs on the physical iPad; the broader Unicode
cases were tested in Python, not in a dedicated native tokenizer unit suite.

## Input/preprocessing boundary

The fixture generator calls the actual worker's `preprocess` on grayscale PIL
images, preserving its crop, aspect resize and normalization behavior. Inputs
are cropped using the worker's white/background rule, resized with longest side
448, normalized using mean 0.9545467 and standard deviation 0.15394445, then
placed at the top left of a zero-filled 448-square tensor. PNGs and little-endian
float32 normalized tensors are saved together.

The native probe reads those tensors directly. It does not yet prove that
Swift/PencilKit PNG → tensor processing matches Python. A future native pipeline
must validate this boundary explicitly; white/zero padding before versus after
normalization, crop threshold and resize interpolation can change predictions.

The six inputs use macOS Chalkboard/STIX fonts and simple drawn fraction/matrix
layouts. They contain no real Pencil strokes. Exact-match scores against these
six synthetic targets would not establish handwriting quality.

## Accuracy findings versus conversion parity

| Fixture | Intended expression | PyTorch reference, also produced by Core ML |
|---|---|---|
| Equation | `x^{2}+3=12` | `Xl+3=12` — incorrect |
| Arithmetic | `2+2=4` | `2+2=4` |
| Algebra | `x^{2}+3x=7` | `x+3x=7` — loses exponent |
| Fraction | `\frac{x+1}{2}` | `\frac{x+1}{2}` |
| Integral | `\int 2x\,dx` | `\int 2xdx` |
| Matrix | `\begin{bmatrix}1&2\\3&4\end{bmatrix}` | `[\begin{matrix}1&2\\ 3&4\end{matrix}]` |

These are direct output strings, not mathematical parser/equivalence results.
The two superscript failures already occur in the reference model. Conversion
preserves those errors. No confidence calibration, candidate ranking, symbolic
parsing or automatic recognition repair is introduced by this experiment.

## Numerical and runtime verification on Mac

Original reference: macOS 26.3.1 arm64, Torch 2.14.1, Transformers 4.44.2,
PEFT 0.13.2, NumPy 2.5.4, Pillow 13.0.0; CPU, four Torch threads.
Conversion: isolated environment with Core ML Tools 9.0, Torch 2.7.1,
Transformers 4.44.2, PEFT 0.13.2, NumPy 1.26.4, Pillow 11.3.0.
Core ML Tools warns that 2.7.0 is its latest tested Torch version; 2.7.1 is
outside that exact tested-version statement. The measured parity results are
the evidence for this specific environment, not a general compatibility claim.

- FP32: all six complete token sequences and EOS match; one trial per fixture.
  Worst encoder absolute error: approximately **1.46e-4**; worst relative L2
  error: **1.52e-5**. Worst first-step logit absolute error: **4.96e-5**.
- FP16: all six complete sequences and EOS match across **three trials each**.
  Worst encoder absolute error: approximately **0.564**, relative L2 **0.0376**;
  worst first-step logit absolute error: approximately **0.714**. This is token
  agreement on these inputs, not a claim that FP16 tensors equal FP32 tensors.
- Numerical comparisons use encoder features and first-step logits, not every
  decoder logit at every position. Token comparisons cover the entire sequence.
- Traced decoder outputs were checked against eager outputs at prefix lengths
  1, 2, 8 and 32. The export permits lengths through 192; exhaustive shape/input
  testing and the token-limit boundary on the real exported model remain open.

Latest Mac FP16 measurements, seconds, CPU/GPU enabled:

| Fixture | Trial 1 | Trial 2 | Trial 3 |
|---|---:|---:|---:|
| Equation | 1.630 | 1.190 | 1.156 |
| Arithmetic | 0.999 | 1.001 | 0.999 |
| Algebra | 1.132 | 1.128 | 1.128 |
| Fraction | 1.277 | 1.283 | 1.290 |
| Integral | 0.865 | 0.775 | 0.722 |
| Matrix | 2.886 | 2.953 | 2.940 |

Loading the two models took approximately 2.30 seconds in this run. These are
sequential measurements in one Mac process; trial 1 is not a controlled cold
machine/cache test. They exclude the recognition debounce, image preprocessing,
model loading and notebook presentation. Earlier runs varied (the first
equation inference was approximately 3.20 seconds). No percentiles or reliable
user-facing latency guarantee can be inferred from this small sample.

## Size and deployment

| Packages | Encoder bytes | Decoder bytes | Combined |
|---|---:|---:|---:|
| FP32 | 343,442,248 | 847,135,588 | approximately 1,135 MiB |
| FP16 | 171,795,575 | 423,815,947 | approximately 568 MiB |

The signed FP16 probe app occupies approximately 573 MiB before distribution
compression. Weight storage is not total runtime memory: graph compilation,
activations, allocator state, GPU buffers and cached runtime resources add to it.
The sampled iPad process footprint reached approximately 1,790 MiB in the matrix
test. Thermal behavior and memory-pressure resilience have not been measured.

The standalone `Folio ML Probe` app builds in Release for iOS, and signs with the
existing development setup. It uses its own bundle ID and does not replace Ink
Pad. Initial installation failed because the remote connection closed; a retry
completed. The self-test then finished with exit code 0 on hardware `iPad13,16`,
with the report's physical-device flag true. Every fixture matched the complete
reference token sequence over all three trials and the final decoded text.

Physical iPad FP16 measurements, seconds:

| Fixture | Trial 1 | Trial 2 | Trial 3 | Sampled footprint MiB |
|---|---:|---:|---:|---:|
| Equation | 3.709 | 1.668 | 1.677 | 1,254 |
| Arithmetic | 1.471 | 1.462 | 1.457 | 1,211 |
| Algebra | 1.676 | 1.679 | 1.671 | 1,194 |
| Fraction | 1.898 | 1.899 | 1.898 | 1,251 |
| Integral | 1.266 | 1.263 | 1.264 | 1,250 |
| Matrix | 4.044 | 3.986 | 3.962 | 1,790 |

Model loading took a further **3.108 seconds**, excluded from the table. This is
a single process launch followed by three consecutive trials per fixture, not
three independent cold launches. With the existing 650 ms debounce, even warm
matrix inference alone would exceed the desired complete interaction budget.

Core ML logged an Espresso `Invalid blob shape` / data-dependent output shape
warning for `logits - [?, 15000]`, then completed every prediction successfully.
The log does not establish the actual operator placement or fallback behavior.
CPU/GPU are enabled; use of the GPU for every component has not been proved.
Investigate output-shape inference and profile execution before integration;
do not suppress this warning or interpret successful execution as proof that
the runtime has an optimal graph.

The app can log three trials per input, exact reference tokens/text, model load
time, hardware identifier, physical-device flag and sampled process physical
footprint. Footprint is sampled after generation steps and can miss transient
peaks; Instruments validation remains necessary for a runtime memory budget.
Cancellation is checked between synchronous Core ML calls and cannot interrupt
an individual prediction. No HTTP/network inference code exists in the probe;
airplane-mode execution has not been tested.

## Tests and remaining acceptance criteria

Passed: five unit/contract tests (blank input, repeatable finite fixture tensors,
EOS/token bounding, tiny split transformer versus full forward, portable Unicode
BPE decoding); real checkpoint greedy reference checks; real Mac FP32 and FP16
Core ML parity; unsigned main-app build; unsigned and signed standalone iOS
probe builds; physical M1 iPad FP16 inference, token/text parity, timings and
sampled memory across 18 fixture inferences. Unit tests are not quality benchmarks.

Still required before calling the offline path viable for the notebook:

1. Profile the dynamic-shape warning and uncached decoder on the physical M1
   iPad; reduce matrix latency and verify the memory budget in Instruments.
2. Establish warm and cold latency on representative real Pencil regions, with
   native preprocessing verified against saved Python tensors.
3. Measure stop-writing → result, including the existing approximately 650 ms
   debounce. That leaves at most about 2.35 seconds for all remaining work.
4. Test longer/more complex expressions, thermal behavior, repeated use, memory
   pressure and cancellation. The uncached decoder is a likely optimization
   target, but this checkpoint has not measured its per-component device cost.
5. Preserve user correction/review before computation; conversion cannot solve
   the observed exponent recognition errors.

## Checkpoint and rollback

Before edits, 261 source files across both repositories were copied, hashed and
accompanied by Git statuses/diffs under
`.reports/on-device-texteller-20261104-224425/`. Original base commits:
labs `63d145b`, Ink Pad `b4cf870`. Existing uncommitted work is included in the
snapshot and must not be discarded using `git reset`.

That directory's `after-manifest.json` lists only this checkpoint's source
changes. `rollback.py` is dry-run by default; `--apply` restores `.gitignore`
and removes only unchanged new source files from this checkpoint. It validates
all post-change hashes first and refuses to proceed if later edits are present.
It does not stop the worker, reset either repo, uninstall apps, remove model
artifacts, or delete either Python environment. No sibling Ink Pad source was
changed by this checkpoint.

## Next decision

Do not connect the solver yet. Physical local inference is demonstrated, but
the baseline exceeds the latency budget for matrices. Profile encoder versus
decoder and investigate output-shape handling and a cached decoder/state
representation before considering smaller models or quantization. If improved
device results are acceptable,
the next change should be a reversible local recognizer provider with native
preprocessing parity and a real Pencil fixture set, followed by editable accepted
expressions. This report does not assert that any of those next steps are done.

Core ML documentation consulted:
[Core ML Tools 9.0 release](https://github.com/apple/coremltools/releases/tag/9.0),
[PyTorch conversion workflow](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html),
and [stateful models](https://apple.github.io/coremltools/docs-guides/source/stateful-models.html).
The current decoder is stateless; stateful/KV-cache conversion remains future work.
