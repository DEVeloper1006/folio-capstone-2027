# Folio native prototype

A Mac notebook with a local typeset shadow. iPad PencilKit source is included, but has not been compiled or device-tested here.

## Local recognition on Mac

The app sends row crops to a loopback-only TexTeller process on port 8002. No image goes to Gemini unless you separately enable cloud consent and click Ask Gemini. Model loading and inference use cached files only. The setup step requires internet access once.

```sh
./scripts/setup-local-ocr
./scripts/run-native
```

Setup downloads about 1.1 GB of model weights plus Python dependencies. Weights live in the Hugging Face cache; dependencies live in `.venv-local-ocr`. The normal browser API environment is unchanged.

The launcher starts the local worker if needed. To run only the worker, use `./scripts/start-local-ocr`.

The default worker profile is `grade12`: TexTeller plus the tested local LoRA adapter in `models/grade12`. The footer shows **TexTeller + Grade 12 adapter (local)** when connected. The worker verifies the base revision and adapter checksums against `config/local-ocr-grade12.json`. Missing or changed adapter files stop startup rather than silently selecting another model. The small adapter is included in source control; setup downloads the larger base model separately.

For a checkout without the adapter, or to revert to the original model, stop the running worker first, then run:

```sh
FOLIO_OCR_PROFILE=base ./scripts/run-native
```

To return to the adapter, stop the base worker and run `./scripts/run-native` without that override. The launcher rejects an existing worker with a different profile. Restart Folio to clear ephemeral drafts after changing models; saved strokes and accepted text remain unchanged. `curl http://127.0.0.1:8002/health` reports the active profile and adapter ID.

Choose Numbers for digits and arithmetic, or Algebra for variables and expressions. Write one expression per row. After a 650 ms pause, the local model reads unresolved rows, newest first. The typeset result appears below its ink preview. Click the row or Use local draft, correct the LaTeX, then Accept transcription. Original strokes remain saved. Incomplete ink is not blocked by inference. Other readings offers alternative model predictions without silently changing your work. Clear page is undoable while the app stays open.

There is one request at a time. Edits coalesce instead of queueing screenshots. Three candidate readings are decoded; Numbers mode keeps only numeric candidates. Unreadable rows are skipped rather than blocking other rows, and transient busy responses receive bounded retries. Responses for older revisions are discarded. Accepted text is never automatically replaced. Retry local reconnects after a failed request. A 16-entry server cache avoids repeating identical inference.

Baseline testing covered 48 numeric font cases, 12 elementary algebra font cases, and 100 real handwriting samples through native capture. With the Grade 12 adapter, the same 100 native handwriting samples improved from 81 to 82 matching first readings and from 91 to 93 matches among three candidates, using limited formatting normalization. Separately, the synthetic expression-held-out test improved from 187/364 to 350/364, and prepared handwriting regression images improved from 67/100 to 76/100. These image pipelines are different and their scores should not be mixed. See [the test report](LOCAL_RECOGNITION_TESTS.md) for timings, failures, methodology, and reproduction commands. These are not general accuracy guarantees. Long expressions can take longer or hit the 192-token limit. Model output is a draft, not verified mathematics.

## Practice examples

Click **Examples** in the top toolbar for 60 searchable references across 10 topics. The gallery starts with Grade 12 calculus; choose **All topics** to browse everything. Each entry shows rendered notation, symbol meanings, the recommended recognition mode, and its LaTeX. Search by name or symbol, including Greek letters. Examples do not alter the notebook and are not recognition guarantees. Matrices, integrals, and complex numbers are marked as extensions beyond Ontario core.

## Checks

```sh
.venv-local-ocr/bin/python -m unittest scripts.tests.test_local_ocr -v
./scripts/test-native
```

The native test runner tests the packaged `.app`, including a rendered `7` in the live draft and a nonblank pixel check. Typesetting uses an explicit file-access grant for bundled KaTeX; plain LaTeX remains visible if rendering fails.

The service tests use a fake recognizer to test validation and HTTP behavior without loading weights. Actual inference was checked separately. Core checks use an executable because XCTest is not installed with this machine's command-line Swift tools.

## iPad

Install full Xcode and XcodeGen. From `native/`, run `xcodegen generate`, open `FolioShadow.xcodeproj`, choose your signing team, and build for iPad. Run the Mac setup/build first to populate the bundled KaTeX resources.

The TexTeller worker currently runs on Mac, not on-device on iPad. Its endpoint remains loopback-only by default. The separate Ink Pad app now has a live rendered-math/LaTeX preview and an optional token-protected LAN connection to this worker; see [the physical-iPad test guide](../../../../ink-pad/docs/recognition-test.md). Set `FOLIO_OCR_LAN=1`, `FOLIO_OCR_ALLOWED_HOSTS` to the Mac IP/hostname, and `FOLIO_OCR_TOKEN` to a random token of at least 24 characters before running `./scripts/start-local-ocr`. LAN mode requires the token for every request, including localhost health checks; stop existing Mac-prototype launchers before using it. On-device Core ML conversion and Pencil latency measurements remain future work. The native document format is not yet compatible with browser `.folio` documents.

## Storage

The native notebook is saved atomically under Application Support/FolioShadow/notebook.json. Undo history and taught symbol examples are session-local. Local model drafts are ephemeral; accept them to persist the transcription.

## Attribution

[TexTeller](https://huggingface.co/OleehyO/TexTeller) is Apache-2.0 licensed. This integration uses checkpoint `7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea`, standard Transformers model classes, and safetensors. Preprocessing follows the model's documented grayscale normalization and padding. No remote model code is executed. Bundled KaTeX retains its MIT license.
