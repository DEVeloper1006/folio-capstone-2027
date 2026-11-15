# Local recognition test report

Tested on this Apple silicon Mac, October 27, 2026. TexTeller checkpoint `7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea`, MPS inference, three decoding candidates, no cloud calls.

## Packaged rendering regression

A user screenshot exposed a blank local-draft box that the earlier build-folder tests missed. Running the same integration check from `Folio.app/Contents/MacOS/FolioNative` reproduced it. `loadHTMLString(baseURL:)` did not provide the packaged view access to its adjacent KaTeX assets.

The renderer now loads a bundled HTML file with explicit read access to its asset directory, passes LaTeX through JavaScript arguments, and displays plain LaTeX until rendering succeeds. Navigation and rendering failures leave that fallback visible. `./scripts/test-native` tests the packaged app, including a drawn `7` in the actual live-draft view and a pixel check rejecting a blank snapshot. Evidence: `artifacts/native-digit-draft.png`.

## Results

| Test | Result |
| --- | --- |
| Numbers mode: digits, multi-digit numbers, signed numbers, decimals, addition and subtraction in three handwriting-style fonts | 48/48 first readings matched |
| Algebra mode: four elementary expressions in the same three fonts | 12/12 first readings matched |
| Algebra mode including isolated digits | 58/60 matched; ambiguous `0` and `7` are fixed by Numbers mode or alternative selection |
| Real handwriting: all 100 examples in the MathWriting test excerpt, rasterized by the native app's `inkPNG` | 81/100 first readings matched |
| Same real-handwriting set, correct reading anywhere in the three candidates | 91/100 |
| Single-expression row grouping on those 100 samples | 100/100 after fixing scale-dependent splitting |
| Model inference on those native crops | Median 0.292 s; 95th percentile 0.463 s; maximum 0.526 s |
| Core regression checks | 10 passed |
| Local service boundary tests | 10 passed |
| Native integration checks | Passed |

The UI waits 650 ms after edits settle before submitting a row. Inference timings do not include that pause or UI rendering. Cold model startup is additional. The font tests are smoke tests, not human handwriting benchmarks. The 100 real samples are a small mixed-complexity regression set, not a claim of general accuracy or a clean held-out evaluation after debugging row grouping on it.

Matching ignores whitespace, `\\left`/`\\right`, spacing commands, simple roman/italic styling, and braces around single-character subscripts/superscripts. It preserves letters, case, digits, operators, and multi-character grouping. Some mismatches are equivalent notation, such as `sin` versus `\\sin`; others are genuine errors, such as `I` versus `2`, missing parentheses, or `omega` versus `w`. No answer-solving or algebraic equivalence was used to make incorrect transcriptions pass.

## Native integration coverage

The `--self-test` mode uses temporary notebooks, not the user's saved document. It checks:

- Actual stroke input for `2+2=4`, native PNG capture, HTTP inference, and selection into the correction field.
- Acceptance preserving original strokes, atomic persistence, undo and redo.
- Clearing a page and undoing the clear.
- Editing during an already-running delayed request: the old `999` response must never be published; only the newer response is shown.
- Switching from Numbers to Algebra while an old request fails: a stale 422 must not block the new mode. Changing mode also clears cloud busy state.
- Bundled KaTeX rendering inside the real Workspace view and a standalone WKWebView.
- Optional real-handwriting fixtures passed through native rasterization and row grouping.

## Fixes made during testing

- Numbers mode filters the model's own candidates to numeric expressions instead of silently changing letters into digits.
- Algebra retains variables and offers alternative readings for explicit selection.
- Larger handwriting no longer splits detached superscript dots and accents into separate rows because of a fixed pixel threshold.
- An unreadable row no longer blocks processing every older row. Failed rows remain visible and editable.
- Busy local inference gets bounded retries, without queueing a screenshot per stroke.
- Single-point strokes display on the Mac canvas.
- Light-mode text remains readable even if the host's appearance is dark.
- The native launcher starts and health-checks the local worker.
- Multiple windows share one notebook and writer rather than overwriting each other's saves.

## Reproduce

```sh
.venv-local-ocr/bin/python -m unittest scripts.tests.test_local_ocr -v
./scripts/test-native
.venv-local-ocr/bin/python scripts/evaluate-local-ocr.py --mode numbers --output artifacts/ocr-numbers-final
.venv-local-ocr/bin/python scripts/evaluate-local-ocr.py --output artifacts/ocr-algebra-final
```

For real handwriting, download the [MathWriting excerpt](https://storage.googleapis.com/mathwriting_data/mathwriting-2024-excerpt.tgz), extract it locally, then run:

```sh
.venv-local-ocr/bin/python scripts/evaluate-local-ocr.py \
  --inkml /path/to/mathwriting-2024-excerpt/test --limit 100 \
  --output artifacts/ocr-human-test
artifacts/Folio.app/Contents/MacOS/FolioNative --self-test --fixtures artifacts/ocr-human-test
```

Detailed results are in `artifacts/ocr-numbers-final/results.json`, `artifacts/ocr-algebra-final/results.json`, and `artifacts/native-fixtures-results.json`. Rendering snapshots are in `artifacts/native-math-check.png` and `artifacts/native-workspace-check.png`. Native view bitmap snapshots may omit embedded WKWebView surfaces; the integration check separately verifies actual KaTeX DOM rendering.

MathWriting attribution: Google Research MathWriting dataset. The archive states CC BY-NC-SA 4.0 for handwriting and CC BY-SA for expressions originating from Wikipedia. Downloaded samples and rendered derivatives are local test artifacts, not bundled app resources or new training data.
