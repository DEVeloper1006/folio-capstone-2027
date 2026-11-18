# Problem-context implementation checkpoints

## Checkpoint 0: repository baseline

- Repository: `DEVeloper1006/folio-capstone-2027`
- Baseline commit: `7ace848` (`Style math captions and source completion overlays`)
- Starting branch: `main`
- Working branch for this increment: `feat/problem-context-compute`
- Toolchain: Xcode 26.2, build 17C52; iOS SDK 26.2.
- Baseline command: `xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj -scheme inkpad -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/folio-problem-baseline build`
- Baseline result: **BUILD SUCCEEDED**.
- Baseline output folder: `/private/tmp/folio-problem-baseline/`.

The baseline is the known-good rollback point. No notebook store or source history was reset. The validated local recognition exports are not in the checkout, so this compile does not validate model inference.

## Checkpoint 1: explicit page-local row grouping

- Changes: optional `Step.problemGroupID`; preview controls to join rows/groups and separate one row; architecture notes; device interaction guide; growing regression checklist.
- Feature build command: `xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj -scheme inkpad -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/folio-problem-feature build`
- Feature result: **BUILD SUCCEEDED**.
- Output folder: `/private/tmp/folio-problem-feature/`.
- Existing warning: `CanvasSmoke.swift` uses deprecated iOS 26 `coordinateSpace`; Xcode also skipped App Intents metadata because the target does not link AppIntents.
- Existing unit tests: `xcodebuild test ... -only-testing:inkpadTests` **TEST SUCCEEDED**; 104 existing test cases passed. The run included computation, recognition, persistence, and expression workflow cases. No test source was added or changed.
- Existing UI interaction tests: **25 passed, 2 failed** (27 cases total). `CanvasUITests.testLibraryNavigationKeepsPenEraserAndLassoConnected` failed at `CanvasUITests.swift:154` because the stroke summary stayed `3 strokes; 64f63cfe4fa7dcd8`. `ComputationUITests.testMatrixComputeInsertMoveUndoAndReopen` failed at `ComputationUITests.swift:54` because direct card dragging did not change the ink stroke summary (`0 strokes; 4dbfb0f27e2ef58a`). The passing cases included row-scoped compute, expression review, recognized-source insertion/reopen, and preview interactions. These failures are in untouched canvas/result-drag areas; do not attribute them to grouping without further investigation.
- Manual interaction: not yet performed on physical iPad. Follow `problem-context-ipad-checklist.md` after installing this branch.

## Checkpoint 2: bounded contextual substitution and solve

- Changes: per-row explicit `Definition` / `Equation to solve` meaning; native AST substitution for accepted, earlier single-symbol definitions in the same group; dependency/cycle and duplicate-definition checks; one remaining variable and degree at most two; contextual results store and validate a complete group source manifest so changed, inserted, reordered, reclassified or ungrouped rows invalidate the result. The preview surfaces the definitions used before **Substitute & Solve**.
- Feature commit: `591eb97` (`Add bounded contextual equation solving checkpoint`); no remote branch, PR or deployment.
- Final simulator build: `xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj -scheme inkpad -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/folio-problem-context-final build` — **BUILD SUCCEEDED**. Output folder: `/private/tmp/folio-problem-context-final/`.
- Final generic iOS device build: `xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj -scheme inkpad -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/folio-problem-context-final-device build` — **BUILD SUCCEEDED**. Output folder: `/private/tmp/folio-problem-context-final-device/`.
- Final focused existing UI checks: **3 passed, 0 failed** on iPad Pro 13-inch (M5), iOS 26.2: `ExpressionWorkflowUITests.testInlineReviewSolveTargetInsertAndReopen`, `PolynomialUITests.testComputeRemoveAndUnsavedRecognitionEditGuard`, and `Calc1UITests.testRowContextAndMenuDoNotCarryOtherRowsResults`. Result bundle: `/private/tmp/folio-context-final-ui/Logs/Test/Test-inkpad-2026.11.18_15-32-57--0500.xcresult`. These exercise adjacent pre-existing preview and computation workflows; none directly covers the new group controls/contextual solve.
- Existing unit checks after the feature implementation: **104 passed** in `inkpadTests`; log: `/private/tmp/folio-context-unit-tests.log`. No test source was added or changed because the repository pauses test development until Saad resumes it.
- Full existing UI suite from checkpoint 1: **25 passed, 2 failed** in canvas/result-drag cases documented above. Those unrelated areas were not changed in checkpoint 2.
- Manual new-flow interaction: not verified. The simulator CUA bridge stopped accepting actions while setting up a scratch notebook, and no physical iPad was available. Use the interaction checklist; report the recognized rows and exact button/menu behavior.
- Build output warnings are existing: deprecated iOS 26 `coordinateSpace` use in `CanvasSmoke.swift` and skipped App Intents metadata because the app target does not link AppIntents.

## Physical iPad installation with local model — November 18, 2026

The initial device installation omitted the ignored model assets and could not provide local recognition. Corrected by staging the original validated exports from `/Users/jasimraza/Desktop/capstone/folio-ipad-labs/results/on-device-texteller` with `ipad/app/scripts/prepare-local-recognition.py`; the script verified package hashes and the pinned model/adapter. Rebuilt for device `00008103-001A28121AE9401E` using `/private/tmp/folio-ipad-connected` derived data. Build log: `/private/tmp/folio-ipad-bundled-model-build.log` — **BUILD SUCCEEDED**.

Before reinstalling, inspected the built app and confirmed `Encoder.mlmodelc` (171,805,182 bytes), `Decoder.mlmodelc` (423,831,708 bytes), `tokenizer-table.json` (206,339 bytes) and `model-manifest.json` (295 bytes). Installation and ordinary app launch both succeeded on the physical iPad Air. This verifies packaging and launch, not a new handwriting inference or grouping interaction run. Model assets remain ignored and uncommitted. Future local-recognition installs must check the actual app bundle before installation.

## Checkpoint 3: automatic context and verification — November 18, 2026

- Replaces manual group membership and role setup with deterministic AST/layout inference on recognition, acceptance and preview open. New optional SwiftData fields cache exact-input native equation ASTs and a user separation override. Existing group/role fields now store inferred semantics; old explicit assignments are recomputed.
- Normal flow: review transcriptions, inspect detected source rows/definitions, then **Verify & Solve**. Needed unaccepted definitions cannot be used, and edited/unaccepted target text disables the action. **Wrong problem? → Separate here** corrects a boundary without configuring mathematical roles.
- Device build: `xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj -scheme inkpad -configuration Debug -destination 'id=00008103-001A28121AE9401E' -derivedDataPath /private/tmp/folio-ipad-connected -allowProvisioningUpdates build` — **BUILD SUCCEEDED**; log `/private/tmp/folio-auto-context-build.log`. An initial compile failed for a missing CoreGraphics import, which was corrected before the passing build.
- Verified `Encoder.mlmodelc`, `Decoder.mlmodelc`, tokenizer and manifest inside the built app before installation. Installation and ordinary launch succeeded on the physical iPad Air, and the app was still present in the running process list after launch.
- Existing automated checks: **104 unit tests passed; 3 focused UI tests passed**, no failures. Focused cases: row context/menu isolation, inline review/solve/insert/reopen and compute/remove/unsaved-edit guard. Log `/private/tmp/folio-auto-context-tests.log`; result bundle `/private/tmp/folio-auto-context-tests/Logs/Test/Test-inkpad-2026.11.18_16-05-53--0500.xcresult`. No test source was added or extended under the repository pause.
- New inference and its corrections are not covered directly by the existing tests. The revised device checklist is the manual handoff; no new handwriting accuracy or automatic grouping interaction claim is made from build/launch alone. Historic notebook migration beyond this installed store is unverified. Layout thresholds are documented heuristics and may join nearby unrelated exercises; users must see the sources before solving.
- Roll back to `c5190a4` for the previous explicit-group workflow with bundled-model installation notes; preserve notebook backups before moving between builds with schema changes.

## Rollback instructions

The feature is isolated on `feat/problem-context-compute`. Checkpoint 1 is committed as `db389e7`; checkpoint 2 is committed as `591eb97`. To return to the untouched baseline, switch to `main` at `7ace848`. To retain the feature locally while returning to baseline work, leave the feature branch intact and switch branches; do not reset a shared branch. No remote branch, pull request or deployment has been created.

