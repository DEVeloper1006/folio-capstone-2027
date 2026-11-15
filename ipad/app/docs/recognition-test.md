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

Use the Mac's Network settings to find its Wi-Fi IP. Copy the token from the terminal environment into the app (for example, `printf '%s' "$FOLIO_OCR_TOKEN" | pbcopy`); do not put it in source control. A running localhost worker must be stopped before starting LAN mode on port 8002. Allow incoming connections if macOS asks. Both devices must be on the same trusted network without client isolation. LAN HTTP is for development testing and is not encrypted. Without FOLIO_OCR_LAN=1, the launcher retains its original localhost-only behavior. LAN mode requires authentication even for localhost requests.

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

Pre-edit checkpoint: `/Users/jasimraza/Desktop/capstone/folio-ipad-labs/.reports/inkpad-recognition-20261028-225041`. Run its `rollback.py` without arguments to preview, or with `--apply` to restore only integration files. It preserves the pre-existing uncommitted Stroke Lab work and refuses to overwrite files edited after the final checkpoint. It does not touch iPad notebooks or app preferences. Stop the worker and select Apple Vision to turn off Mac recognition without reverting code. The checkpoint lives in the labs repository’s ignored `.reports` directory. It contains the original file copies, implementation snapshots, validation logs, and the private development connection settings.

## Validation on October 28, 2026

- 22 iPad simulator unit tests passed, including packaged MathJax rendering, cancellation/retry, stale-response rejection, worker failures, and the existing Stroke Lab checks.
- 16 Mac worker boundary tests passed, including LAN authentication and host restrictions.
- Debug and Release device builds passed without signing; Release was checked to exclude the development HTTP override.
- The real Grade 12 worker correctly read two generated smoke inputs (`2+2=4` and `x^2+3x=7`). These are not Apple Pencil accuracy measurements.
- Xcode detected the paired iPad Air but timed out waiting to reconnect, so installation and physical Apple Pencil testing remain to be completed with the iPad awake and connected.

For this Mac’s prepared connection, private details are in `folio-ipad-labs/.reports/inkpad-recognition-20261028-225041/connection.json`. The worker was started at `http://192.168.40.49:8002`. After stopping an existing worker, restart the same private configuration from the labs root with `python3 .reports/inkpad-recognition-20261028-225041/start-worker.py`. If the Mac IP changes, update the private URL, the allowed host in that helper, and the app settings.

## If the connection times out

The Mac Wi-Fi IP can change between networks. The development launcher now detects the current IP and allows the Mac’s stable `.local` hostname too. Start it from the labs root with:

```sh
python3 experiments/folio-workspace/scripts/start-ipad-ocr
```

To preserve the already prepared token instead, use `python3 .reports/inkpad-recognition-20261028-225041/start-worker.py`. Stop an existing worker first. The launcher prints the hostname URL, current IP fallback, and private connection-file path. Update the URL in Ink Pad settings; existing saved URLs cannot update themselves. Both devices must share a network that permits local device connections. If `.local` resolution is unavailable, use the printed numeric IP.

A browser visit without a bearer token should return an authentication error promptly. Use `/health` rather than the root URL to check the service. A timeout indicates reachability, not a wrong token. The app’s Test connection now fails after five seconds with address and local-network permission guidance.
