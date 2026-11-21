# Build Folio and run it on your iPad

This guide is for a teammate building from a fresh checkout on their own Mac and installing on their own iPad. It covers the native app and bundled local handwriting model. A successful compile alone does not establish that the model is bundled or that recognition works on your device.

## What you need

- A Mac with Xcode, its command-line tools, and the iOS SDK installed. This checkpoint was built with Xcode 26.2; the current app requires iPadOS 26.2 or newer.
- An Apple account added in **Xcode → Settings → Accounts**, with a development team available for signing.
- An iPad connected to the Mac, unlocked, trusted, and available as an Xcode run destination. Use USB for the first installation.
- Repository access and the separately shared **validated local-recognition export artifacts**. These large models are intentionally excluded from Git. Cloning or pulling the repository does not download them.

Read the root [AGENTS.md](../../../AGENTS.md) and [CONTRIBUTING.md](../../../CONTRIBUTING.md) before changing code. The repository pause on adding/extending tests still applies; running existing tests is allowed.

## 1. Get the source

```bash
git clone https://github.com/DEVeloper1006/folio-capstone-2027.git
cd folio-capstone-2027
git switch --track origin/feat/linalg-recognition-idle
xcodebuild -version
```

The feature branch contains the four-second LINALG idle policy and bracket-aware matrix recognition. It has not been merged into `main` by this handoff. If the branch is already checked out, use `git switch feat/linalg-recognition-idle`. If continuing existing work, inspect `git status` first and preserve local edits; do not reset the checkout to follow this guide.

If Xcode is installed but command-line tools select a different installation, choose the intended Xcode under **Xcode → Settings → Locations → Command Line Tools**, then rerun `xcodebuild -version`.

## 2. Stage the local recognition model BEFORE building

Ask the project maintainer for the validated `on-device-texteller` export folder or its shared archive. Do not substitute an arbitrary downloaded TexTeller model, an unmerged adapter, or files from a built `.app`. The staging script verifies the pinned base/adapter and export package hashes; it does not download or convert models.

The artifact folder must contain:

```text
on-device-texteller/
├── reference.json
├── export-encoder-fp16.json
├── export-decoder-fp16.json
├── fixtures/tokenizer-table.json
└── models/fp16/
    ├── Encoder.mlpackage/
    └── Decoder.mlpackage/
```

Keep this folder outside Git. From the repository root, replace the example absolute path with its actual location:

```bash
python3 ipad/app/scripts/prepare-local-recognition.py \
  --artifacts /absolute/path/to/on-device-texteller
```

The command must print **Staged validated local TexTeller resources**. It writes to `ipad/app/inkpad/inkpad/Resources/LocalTexTeller/`, including the tokenizer and generated manifest. Xcode compiles the packages into the app through the existing filesystem-synchronized group. Stage assets in the exact checkout/worktree you are building, then rebuild; staging a different checkout does not update this one. Do not commit the generated resources or model archive.

If using the previously shared archive named `Folio-validated-local-recognition.tar.gz`, the SHA-256 of that particular archive is `c5747706b9eb308ebb7812ae182c76614803091b58ca4536b43b6860e84b19f5`. Compare using `shasum -a 256 /path/to/Folio-validated-local-recognition.tar.gz`, extract outside the repository, and locate the folder containing `reference.json` before running the command above. This checksum is not a download link or the checksum of every possible repackaging. If you do not have the artifacts, obtain them first; an empty source-only checkout cannot provide local model recognition.

## 3. Configure signing for YOUR iPad

```bash
open ipad/app/inkpad/inkpad.xcodeproj
```

In Xcode:

1. Select the **inkpad** project, then the **inkpad** app target and **Signing & Capabilities**.
2. Enable **Automatically manage signing** and select **your own team**. The checked-in team belongs to another developer; do not assume your Mac can use it.
3. If Xcode cannot register `com.dev.inkpad` for your team, choose your own unique bundle identifier, such as `com.yourname.folio`. Record the identifier for later commands. A different identifier installs a separate app with a separate notebook store; existing notebooks will not appear there automatically.
4. Select the **inkpad** scheme and your connected iPad as the run destination.
5. Resolve signing/account/device-registration messages in Xcode. Keep machine-specific signing changes local unless the team deliberately agrees to change the shared project.

On the iPad, accept a **Trust This Computer** prompt if shown. Enable **Developer Mode** under **Settings → Privacy & Security** if Xcode requests it, completing the device restart/confirmation it requires. A developer-trust item under **VPN & Device Management** may only appear when a profile actually requires approval; an empty screen there does not by itself identify the installation problem. Follow the specific Xcode/device prompt.

## 4. Build and install

### Recommended: Xcode Run

With the model already staged and your signing configured, press **Run**. Keep the iPad unlocked and awake through installation. The first model compilation/transfer can take several minutes. Xcode should report a successful build and launch Folio on the selected iPad.

### Optional: command-line device build

Run from the repository root after configuring the signing account. Replace the team and bundle identifiers below with yours. Build-setting overrides avoid changing shared signing settings just for this command:

```bash
xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj \
  -scheme inkpad -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/folio-ipad-build \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  PRODUCT_BUNDLE_IDENTIFIER=com.yourname.folio \
  build > /tmp/folio-ipad-build.log 2>&1
```

Check the command's exit status and the end of `/tmp/folio-ipad-build.log`; require **BUILD SUCCEEDED** before installation. `CODE_SIGNING_ALLOWED=NO` is useful for some compile checks but does not produce a normally installable, signed device app.

## 5. Verify the built app contains the models

For the command-line build above, run:

```bash
python3 - <<'PY'
from pathlib import Path
app = Path('/tmp/folio-ipad-build/Build/Products/Debug-iphoneos/inkpad.app')
if not app.is_dir():
    raise SystemExit('Built app not found; check the build log and derived-data path.')
required = ['Encoder.mlmodelc', 'Decoder.mlmodelc', 'tokenizer-table.json', 'model-manifest.json']
missing = []
for name in required:
    found = list(app.rglob(name))
    print(name, 'PRESENT' if found else 'MISSING')
    if not found:
        missing.append(name)
if missing:
    raise SystemExit('Model bundle incomplete: ' + ', '.join(missing))
PY
```

For an Xcode GUI build, find `inkpad.app` under **Products → Show in Finder** and use its actual path as `app` in the check. Verify the built `.app`, not only the source resource folder. If any item is missing, restage in the correct checkout, rebuild and recheck before calling the installation ready.

For a command-line installation, list devices and copy your own iPad identifier from the output:

```bash
xcrun devicectl list devices
xcrun devicectl device install app \
  --device YOUR_IPAD_IDENTIFIER \
  /tmp/folio-ipad-build/Build/Products/Debug-iphoneos/inkpad.app
xcrun devicectl device process launch \
  --device YOUR_IPAD_IDENTIFIER \
  com.yourname.folio
```

Require **App installed** and a successful launch, or use Xcode Run instead. Keep the identifier consistent with the app you built. If a running app prevents launch, close Folio and retry through Xcode; do not delete it to resolve a transient error.

## 6. Check it on your iPad

1. Open/create a notebook. In recognition settings choose **Local TexTeller (on iPad)** if another provider was previously selected. Local recognition needs no Mac endpoint, server address or API token.
2. Write a simple expression, tap **Recognize**, and confirm a draft appears. Review/correct it before accepting. Bundled-model presence and actual inference are separate checks.
3. With automatic recognition enabled, LINALG waits four seconds after Pencil lift/new ink; CALC and PROOF retain the existing 0.65-second delay. Manual Recognize remains immediate.
4. Try a complete square-bracketed 2×2 matrix, then a larger matrix. Expect one region and verify every entry. Current cell extraction targets 2–6 rows and 1–6 columns; fractions, augmented bars, parentheses and ambiguous grids are not established as supported. Large matrices use one model call per cell and can take substantially longer than a single expression.
5. Confirm writing, erasing, undo, saving/reopening and result insertion still work. Back up notebooks before any reinstall, identifier change or migration experiment. Deleting the app can delete its local notebook data.

Use the [matrix guide](matrix-recognition.md), [iPad interaction checklist](problem-context-ipad-checklist.md), [integration mini demo](integration-mini-demo.md) and [major-version regression checklist](problem-context-regression.md) for expected results and feedback. The real-ink matrix diagnostic read 58/60 entries correctly on the Mac; it does not establish accuracy or speed on every iPad.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| “Local math model is not bundled” | Stage validated artifacts in this checkout, rebuild, inspect all four resources inside the built app, then install that exact build. Pulling Git alone does not supply the models. |
| Missing `reference.json`, export manifest, or package hash failure | Obtain the complete matching validated export folder. Do not bypass validation or change hashes to accept unknown artifacts. |
| “Requires a development team” or signing/profile errors | Select your account/team in the app target; use a bundle identifier your team can register and the actual connected device destination. Read Xcode's specific provisioning error. |
| Device unavailable or locked | Connect by USB, unlock, accept any Trust prompt, keep it awake, and confirm it appears available in Xcode or `devicectl list devices`. |
| Install succeeds but launch is denied | Check Developer Mode and the specific trust/signing message, then rebuild/run with your own team for the connected iPad. Development profiles can expire; refresh them through Xcode when prompted. |
| Simulator works but device does not | Verify iPadOS meets the 26.2 deployment target, device signing succeeds, models are in the device `.app`, and local inference actually runs. Simulator execution is not physical-device verification. |
| Matrix appears in pieces | Complete both square brackets and retry **Recognize** on this feature build. Check the bounds/grid and report expected/actual dimensions. Incomplete or ambiguous matrices need review. |
| Matrix contains `u`/`s` where you wrote `4`/`5` | Correct the recognition draft; these model character confusions remain possible. Do not accept incorrect entries merely because the grid is rectangular. |

## Existing checks and handoff evidence

To compile for a simulator without installing on an iPad:

```bash
xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj \
  -scheme inkpad -destination 'generic/platform=iOS Simulator' build
```

To run the existing units and the selected drawing interaction test, first find an available iPad simulator with `xcrun simctl list devices available`, then substitute its UUID:

```bash
xcodebuild test -project ipad/app/inkpad/inkpad.xcodeproj \
  -scheme inkpad -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO \
  -only-testing:inkpadTests \
  -only-testing:inkpadUITests/ExpressionWorkflowUITests/testAutomaticRecognitionLeavesCanvasWritableAndDoesNotOpenPreview
```

This checkpoint passed 104 existing unit tests and that one UI test on the development Mac. No test code was added. These checks do not prove matrix-model accuracy on a new device. Record the Git commit, Xcode/iPadOS versions, iPad model, signing bundle identifier, model-bundle check, build/install/launch results and first incorrect `(row, column)` when reporting a problem. Keep private notebook/ink exports, development profiles and generated models out of Git. See [build checkpoints](problem-context-checkpoints.md) for exact prior execution status and rollback guidance.
