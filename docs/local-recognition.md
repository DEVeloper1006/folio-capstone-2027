# Local recognition and accepted notebook expressions

This milestone integrates the validated TexTeller Core ML model into Ink Pad.
Recognition is manual: write in a notebook, tap **Recognize**, review/edit LaTeX,
and **Accept & Save**. No solver or mathematical verification is added.

## Use

Open a notebook, use the network/settings icon, choose **Local TexTeller (on
iPad)** and Save. No address/token is required. **Mac TexTeller** and the Apple
Vision baseline remain selectable; existing saved provider preferences are
preserved. New installations default to Local. Local errors are shown rather
than silently calling another provider. Mac HTTP remains development-only.

Write one expression per spatial row, then tap **Recognize** in the toolbar or
preview. The preview appears beside the canvas in wide windows and as a sheet
in narrow windows. It shows typeset math, an editable LaTeX field, alternatives
when supplied by the provider, and request duration. **Use** selects an alternative
for review. **Accept & Save** explicitly persists the transcription. Mathematical
status remains unchecked. Changing providers or recognizing again preserves an
accepted correction while its ink is unchanged. Edit ink to require new
recognition; previous accepted revisions retain the previous strokes.

This version intentionally removes automatic recognition scheduling. Drawing
still saves locally, but model inference runs only after the button is pressed.
Editing ink, changing providers/modes, leaving the notebook or backgrounding the
app cancels the current request. Cancellation takes effect between Core ML
predictions; an active synchronous prediction cannot be interrupted. Drawing
and raw results are guarded against stale asynchronous commits.

## Source architecture

- `Services/LocalMathRecognitionService.swift` adapts the shared recognition
  protocol to the bundled model, with one uncalibrated greedy candidate.
- `Services/LocalTexTellerRuntime.swift` caches one encoder/decoder pair on an
  actor outside the UI actor, reuses the proven byte-level BPE decoder and caps
  generation at 192 new tokens. CPU/GPU are enabled; operator placement is not
  guaranteed. It checks the pinned model revision.
- `Services/ImagePreprocessor.swift` reproduces the tested grayscale crop,
  Pillow-compatible bicubic resampling, 448-square normalized-space padding and
  normalization. Declarations explicitly opt out of the project's default UI
  actor isolation. The mathematical preprocessing is copied from the probe.
- `Services/RecognitionConnection.swift` routes Local/Mac/Vision explicitly and
  provides the settings UI. Mac request/health/authentication handling remains.
- `Services/InkSegmentationService.swift` retains the existing spatial grouping
  thresholds. Its SHA-256 fingerprint now covers canonical point attributes,
  transforms, bounds, ink/color and erasure masks, rounded to 1e-4. Native
  archives contain fresh IDs and cannot themselves be used as stable hashes.
- `Services/StepTrackingCoordinator.swift` matches rows, rejects cancelled/stale
  results, and skips accepted rows unless their content changes. Legacy
  fingerprints are rematched by bounds; rows may need one new recognition.
- `Services/ExpressionReviewService.swift` validates the current row and saves
  accepted text, its ink association and an accepted revision. It rejects empty,
  oversized and stale corrections. Save errors are visible in the preview.
- `App/Views/NotebookView.swift` controls manual inference, explicit background
  saves, provider switching and acceptance. `RecognitionPreviewView.swift` owns
  editable review fields and continues to use bundled MathJax.

## Model setup

The approximately 568 MiB FP16 Core ML packages are generated resources, ignored
by Git. The app's filesystem-synchronized Xcode source group compiles them into
its bundle. Reproduce staging with the exports from the adjacent labs repo:

```sh
python3 scripts/prepare-local-recognition.py --artifacts ../folio-ipad-labs/results/on-device-texteller
```

The script checks exported package SHA-256 hashes and the pinned adapter/base
before copying resources. It downloads nothing. Missing resources produce a
visible local-model error; use Mac until the models are staged and rebuilt.

Base: `OleehyO/TexTeller`, revision
`7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea`. Adapter:
`grade12-pilot-500`, SHA-256
`001fdbd1e34661c007a286c04c405d21d56cab71c5006c16e4f56542af4ab6db`,
merged before export. The decoder is greedy and uncached; production Mac beam
search can produce different outputs. The existing Core ML dynamic output-shape
warning and roughly four-second matrix inference remain open. The app does not
claim the three-second complete interaction goal is met. Loaded model resources
remain cached until the app exits, including after switching to Mac.

## Persistence and benchmark collection

`Step` gains defaulted acceptance/provider/duration fields. Acceptance preserves
`recognizedText` (the model output), sets the corrected `ghostLaTeX`, and stores
`acceptedLatex`, `acceptedFingerprint` and `acceptedAt`. `StepRevision` gains a
user-accepted marker and provider, while retaining native ink bytes and LaTeX.
These are additive SwiftData changes. Raw page drawings remain in `Page`.

Acceptance also writes an independent local example under
`Documents/RecognitionBenchmarks/<UUID>/`: `strokes.drawing`, `input.png` and
`result.json`. The metadata includes provider, model prediction, user-reviewed
expected LaTeX, request time, fingerprint and (for Local) pinned base revision.
No upload is implemented. If example export fails, the UI says the notebook
expression was saved but the export failed. Notebook acceptance does not depend
on a network service or successful benchmark export.

Collect 15–20 real examples covering arithmetic, powers/subscripts, fractions,
integrals and small matrices. Correct the transcription before accepting. Copy
RecognitionBenchmarks from the app data container, then summarize with:

```sh
python3 scripts/summarize-recognition-benchmark.py /path/to/RecognitionBenchmarks
```

The summary excludes generated smoke examples and reports literal LaTeX matches
and recognition timings. It does not assess symbolic equivalence, calibrated
confidence or held-out accuracy. Request timings include capture/preprocessing
and initial model loading; they exclude row bookkeeping, debug logging,
review, saving and visible MathJax presentation. Real human benchmark collection
is still required; no accuracy percentage is asserted by this implementation.

## Verification and rollback

Thirty-one simulator tests pass, including provider routing, corrected expression
persistence in a reopened disk container, preserved raw ink/revisions, dark-mode snapshot foreground, stale
acceptance rejection, cancelled/delayed recognition, deleted/edited ink,
accepted-row protection across provider changes, bundled MathJax rendering,
segmentation and existing Stroke Lab behavior. Model responses in these tests
use mocks; they do not measure real inference accuracy.

Two initial simulator crashes traced to actor-isolated object destruction in
this toolchain. Stateless Vision/Mac services now use structs; StrokeLabSession
has an explicit nonisolated empty deinitializer. The complete suite passed after
those fixes. Full-content fingerprint tests then caught non-deterministic native
archive IDs; canonical hashing resolves that without changing grouping thresholds.

The optimized Debug device build succeeds (retains development Mac HTTP support).
The explicit debug launch flags `--local-integration-smoke` and
`--local-integration-reopen` exercise the real model and a separate persistent
notebook store, then verify it across app processes. They do not insert generated
notebooks into the user's library. Physical verification passed on the M1 iPad Air: the generated PencilKit X was
recognized as `x`, corrected to `x^{2}`, accepted and written to a separate
notebook store, then reopened and verified in a second app process. The original
ink, model output, accepted revision and corrected text survived. The existing
user library opened after the additive schema migration and retained the same
five notebooks and seven pages as the pre-migration backup. No synthetic pages
were inserted into that library. The generated benchmark case records 5,520 ms
for recognition; this single run is not a performance benchmark.

The first physical run found a blank snapshot under dark appearance. Export now
forces a light trait against the white background, and a foreground regression
test covers dark-mode capture. The repaired physical run and relaunch exited 0.
Core ML still logs the known dynamic-shape warning. Development builds also log
an LLVM profile-file write warning on forced smoke-test exit; the functional
checks succeeded. Human handwriting quality and manual UI acceptance still
require user testing.

Checkpoint in the labs repository:
`.reports/inkpad-local-integration-20261105-001115/`. It preserves both repositories'
pre-existing uncommitted source (276 files), an installable pre-change Ink Pad app,
and copies of this iPad's existing Application Support database and Documents.
A guarded source rollback is provided there. Rollback validates current hashes
and refuses to overwrite subsequent edits. It does not reset Git or silently
restore device data. Reinstalling the older app after a schema migration may
also require the pre-migration database backup; restoring that backup would
replace notebook edits made since it, so device data restoration is a separate,
explicit recovery operation. New accepted revisions have no backward
interpretation in the earlier app.

## Limits

Grouping is still heuristic; no new split/merge or manual-region editor is added.
Recognition cannot guarantee valid or mathematically correct LaTeX. Accepted text
has no mathematical IR, parsing, solving, automatic steps or result insertion.
Accepted rows are deliberately skipped by re-recognition; edit their ink or edit
and re-accept the text to change them. Benchmarks are local convenience samples,
not a trained model update. Offline model size, runtime memory and decoder latency
remain significant. The separate probe and Mac worker are left available.
