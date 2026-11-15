# Apple Pencil → Mac TexTeller → live LaTeX

This development integration sends row PNGs to the local Mac worker. The model runs on the Mac; no Core ML export is required. Original PencilKit strokes remain unchanged. Results are unchecked drafts, not mathematical verification.

## Start the Mac

From `../folio-ipad-labs/experiments/folio-workspace`:

```sh
./scripts/setup-local-ocr
export FOLIO_OCR_LAN=1
export FOLIO_OCR_ALLOWED_HOSTS="192.168.1.20" # replace with your Mac's Wi-Fi IP
export FOLIO_OCR_TOKEN="$(openssl rand -hex 24)"
./scripts/start-local-ocr
```

Use the Mac's Network settings to find its Wi-Fi IP. Copy the token from the terminal environment into the app; do not put it in source control. A running localhost worker must be stopped before starting LAN mode on port 8002. Allow incoming connections if macOS asks. Both devices must be on the same trusted network without client isolation. LAN HTTP is for development testing and is not encrypted. Without FOLIO_OCR_LAN=1, the launcher retains its original localhost-only behavior. LAN mode requires authentication even for localhost requests.

## Open on the iPad

1. Open `inkpad/inkpad.xcodeproj`, choose your connected iPad and signing team, and run the **Debug** configuration.
2. In a notebook, tap the network icon (**Handwriting recognition settings**).
3. Choose **Mac TexTeller**, enter `http://192.168.1.20:8002` using your Mac IP, and paste the token. Tap **Test connection**, then **Save**. Allow local-network access when prompted.
4. Open **Typeset** from the toolbar or command palette. In landscape with enough width, the preview sits beside the ink; smaller windows use a bottom sheet.
5. Write one expression per row. Pause briefly to see rendered math, selectable raw LaTeX, alternatives, and copy actions. The request timing includes transport and bounded busy retries; the 650 ms debounce is additional.

Try `2+2=4`, `x^2+3x=7`, a stacked fraction, a square root, then several separate rows. Edit while a request is running, erase a row, disconnect/reconnect Wi-Fi, and use Retry. Old output is labelled stale while being updated. Settings persist on this device. The token is a development connection credential stored in app preferences; do not reuse a production secret.

Apple Vision remains the default provider. Switching providers rereads active inferred rows. TexTeller has no calibrated confidence score, so output remains a reviewable draft. Reopening a saved notebook preserves ink and previous LaTeX, while alternatives and timings are session-local.

## Tests and rollback

Run `xcodebuild test -project inkpad/inkpad.xcodeproj -scheme inkpad -destination 'platform=iOS Simulator,name=<installed iPad simulator>' -only-testing:inkpadTests`.

Worker tests run from the labs workspace with `.venv-local-ocr/bin/python -m unittest scripts.tests.test_local_ocr -v`. They mock the model; a real Apple Pencil smoke test is still required to establish recognition quality.

Pre-edit checkpoint: `/private/tmp/inkpad-recognition-20261028-225041`. Run its `rollback.py` without arguments to preview, or with `--apply` to restore only integration files. It preserves the pre-existing uncommitted Stroke Lab work and refuses to overwrite files edited after the final checkpoint. It does not touch iPad notebooks or app preferences. Stop the worker and select Apple Vision to turn off Mac recognition without reverting code. Copy the checkpoint somewhere durable if needed; `/private/tmp` is temporary storage.
