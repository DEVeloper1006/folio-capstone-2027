# TexTeller local Core ML feasibility probe

This isolated experiment merges the existing Grade 12 LoRA into the pinned
TexTeller base, exports encoder and uncached decoder components, checks numerical
and greedy token parity, and builds a separate iPad probe. It does not change
Ink Pad or its HTTP recognition backend. See
[the feasibility report](../../../../docs/ml/ON_DEVICE_TEXTELLER_FEASIBILITY.md)
for measured results and limitations.

## Reproduce

Run commands from the repository root. Model files and the Grade 12 adapter must
already exist in the local Hugging Face cache and workspace. Model loading is
offline; this script does not fetch missing checkpoints. Dependency installation
requires network access. Fonts used by the synthetic fixtures are macOS system
Chalkboard and STIX Two Math.

```sh
experiments/folio-workspace/.venv-local-ocr/bin/python -m venv experiments/folio-workspace/export/texteller/.venv
experiments/folio-workspace/export/texteller/.venv/bin/python -m pip install -r experiments/folio-workspace/export/texteller/requirements.txt
```

Generate goldens with the original recognition environment, not the conversion
environment. This loads the real model and takes time. It verifies uncached
greedy generation against Hugging Face cached greedy generation. Production
beam search is a separate mode and is not the parity target.

```sh
experiments/folio-workspace/.venv-local-ocr/bin/python experiments/folio-workspace/export/texteller/probe.py reference --device cpu
```

Export each component separately to keep conversion memory bounded. Repeat the
two export commands with `--precision fp32` for the numerical baseline.

```sh
experiments/folio-workspace/export/texteller/.venv/bin/python experiments/folio-workspace/export/texteller/probe.py export-encoder --precision fp16
experiments/folio-workspace/export/texteller/.venv/bin/python experiments/folio-workspace/export/texteller/probe.py export-decoder --precision fp16
experiments/folio-workspace/export/texteller/.venv/bin/python experiments/folio-workspace/export/texteller/probe.py validate --precision fp16 --trials 3
experiments/folio-workspace/export/texteller/.venv/bin/python -B -m unittest discover -s experiments/folio-workspace/export/texteller -p 'test_*.py' -v
```

`results/on-device-texteller/` contains ignored model packages, fixture PNGs,
normalized tensors, reference NPZ arrays, tokenizer bytes, numerical comparisons,
timings and package hashes. Do not commit generated model weights. The five unit
tests use a tiny randomly initialized transformer or fake decoder, except the
tokenizer test, which requires the already cached tokenizer; none loads the
real recognition checkpoint.

## Standalone iPad app

```sh
experiments/folio-workspace/export/texteller/.venv/bin/python experiments/folio-workspace/export/texteller/prepare_app.py --precision fp16
xcodebuild -project experiments/folio-workspace/export/texteller/ProbeApp/TextellerProbe.xcodeproj -scheme TextellerProbe -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/folio-texteller-probe CODE_SIGNING_ALLOWED=NO build
```

`prepare_app.py` stages ignored model symlinks and fixture resources. It generates
the Xcode project using the existing sibling Ink Pad signing team, or an explicit
`--team TEAM_ID`. Open the generated project in Xcode, select the iPad Air, and
build/run with signing enabled. Bundle ID: `com.dev.inkpad.textellerprobe`;
display name: **Folio ML Probe**; minimum iPadOS: 18.0.

The app has a **Run all six fixtures** button. `--self-test` auto-runs three trials
per fixture and exits with 0 for token/text parity, 2 for a difference, or 3 for
an execution error. It prints JSON markers `FOLIO_PROBE_RESULT` and
`FOLIO_PROBE_SUMMARY`, and writes `Documents/device-results.json` in its own app
container. Device installation/launch can use Xcode or `xcrun devicectl`.

The **Write** tab now captures PencilKit input and shows typeset math plus raw
LaTeX next to it (stacked in narrow windows). Tap **Recognize** manually. It saves
raw PencilKit data, a white-background region PNG, a normalized tensor and result
JSON in `Documents/Handwriting/<UUID>/`. Enter optional expected LaTeX **before**
recognizing to label an example. **Clear** only clears the canvas. The local Files
app exposes saved examples under Folio ML Probe; nothing is uploaded.

The Swift actor runs Core ML off the main actor, with CPU/GPU enabled. Both tabs
share one model instance. A bounded greedy token loop and byte-level BPE decoder
produce LaTeX. The Write tab uses native Pillow-compatible preprocessing and
bundled MathJax. It makes no HTTP requests. The fixture timings still exclude
model loading and image preprocessing. Write-tab timings separately report
preprocessing, model preparation, encoder/decoder, and capture-to-decoded time;
the last excludes persistence, typesetting and screen presentation. There is no
automatic debounce in this probe. Memory is sampled process physical footprint,
not an Instruments peak. See [the handwriting checkpoint](../../../../docs/ml/PENCIL_RECOGNITION_PROBE.md).

Native preprocessing verification (requires the existing fixtures and Python
environment, no model weights are loaded):

```sh
swiftc -O experiments/folio-workspace/export/texteller/ProbeApp/ImagePreprocessor.swift experiments/folio-workspace/export/texteller/tests/PreprocessCheck.swift -o /private/tmp/folio-preprocess-check
experiments/folio-workspace/export/texteller/.venv/bin/python experiments/folio-workspace/export/texteller/verify_preprocessing.py --binary /private/tmp/folio-preprocess-check --report results/on-device-texteller/native-preprocessing/contracts.json
```

`--pencil-smoke-test` runs a generated two-stroke PencilKit X through the actual
capture/recognition/persistence/typesetting path, then exits 0 only after a local
SVG preview is produced. It is a synthetic smoke test, not a human accuracy test.
Copy a saved example from the device and check its tensor/text with:

```sh
experiments/folio-workspace/export/texteller/.venv/bin/python experiments/folio-workspace/export/texteller/verify_saved_example.py /path/to/copied/example
```

## Checkpoint and rollback

The pre-change snapshot is under
`.reports/on-device-texteller-20261104-224425/`, including both repositories'
existing dirty source state. Its `rollback.py` is dry-run by default and restores
only this checkpoint's listed source changes when passed `--apply`. It verifies
post-change hashes before restoring anything and refuses to overwrite later
edits. Read the feasibility report before rollback. Generated weights, the
isolated virtual environment and the installed probe are deliberately retained;
the existing app and worker are independent of them.

The later drawing checkpoint is `.reports/pencil-probe-20261104-232630/`, with
the immediately previous source and signed app. Roll this checkpoint back first
before attempting the earlier baseline rollback. Each rollback validates hashes
and refuses to overwrite subsequent edits; run without `--apply` to review it.
