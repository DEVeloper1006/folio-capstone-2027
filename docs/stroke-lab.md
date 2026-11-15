# Folio Stroke Lab — Milestone 1

For the ordered iPad collection session and data-transfer instructions, start with [the capture worksheet](stroke-capture-worksheet.md).

Stroke Lab collects real handwriting and manual spatial annotations for future grouping evaluation. Open **Folio → Stroke Lab** in the library toolbar. No recognition, automatic grouping, parsing, Math IR, or network service runs in this screen.

## Repository inspection and implementation boundary

The existing application is an iPhone/iPad SwiftUI app with SwiftData notebook/page storage. The checked-in Xcode project uses Swift 5 language mode, a default MainActor isolation setting, and iOS 26.2 deployment targets. Xcode 26.2 is installed in the development environment. There is no separate native macOS app target. The new data types, exporter, and document code also compile in a macOS command-line harness; the capture UI remains iPad/iPhone UIKit code.

Existing `InkCore/CanvasView.swift` wraps `PKCanvasView`; `CanvasViewModel` manages tools and debounced notebook saves. `PKStrokeProvider` offers a small location/force/time representation for existing services. `Page.drawingData` stores native PencilKit bytes. Existing segmentation/recognition services and their tests remain in place. The preexisting UI tests mostly exercise launch. The design folder contains HTML mockups, tokens, an image, and bundled MathJax; no existing stroke collection contract or collection guide was found.

Stroke Lab has its own canvas coordinator because the notebook canvas has notebook-specific autosave/tool behavior and feeds existing mathematical processing. Reusing `PKCanvasView`, `PKDrawing`, and the current library navigation avoids replacing those components or changing the SwiftData schema. The only library change is the entry link. No existing notebook drawings are migrated or silently imported.

## Architecture and data flow

```text
Apple Pencil → PKCanvasView → PKDrawing
                              ├─ drawing.pkdrawing (native source)
                              └─ LabExport → LabRawPage → strokes.json
Stroke list selection → manual expression/row operations → annotations.json
                                              ↓
                shared JSON Schema + semantic validation + native consistency
                                              ↓
                           atomic local .folioink package save / explicit export
```

Files in `inkpad/inkpad/StrokeLab`:

| File | Responsibility |
| --- | --- |
| `StrokeLabContract.swift` | Foundation-only Codable values, affine transform math, manual annotation operations, reference and hierarchy validation |
| `StrokeLabDocument.swift` | PencilKit adapter, stable identity fallback, FileDocument export, local package storage, native/portable consistency checks |
| `StrokeLabSchema.swift` | Evaluates the JSON Schema vocabulary used by v1 against the bundled schema |
| `stroke-lab-v1.schema.json` | Authoritative Draft 2020-12 structural contract, bundled by the synchronized Xcode project group |
| `StrokeLabView.swift` | Independent drawing canvas, selection list, inspection, group/row editing, persistence and export controls |

The schema validates an envelope `{"raw": <strokes.json>, "annotations": <annotations.json>}`. The two objects are stored separately in a package so raw handwriting remains independent of ground truth. Swift validates against the actual bundled schema before export and when opening, then checks references, timestamps, revisions, and hierarchy rules. Reexporting native drawing data must reproduce the portable page exactly. Failures are reported; they do not reset a corrupt page to a blank one.

The Swift and Python evaluators intentionally support only the vocabulary present in v1 and reject unknown keywords. The schema can also be used by a complete Draft 2020-12 validator. A structural validator alone cannot enforce cross-file references, cyclic hierarchies, or native fidelity; the semantic checks remain necessary.

## PencilKit APIs and compatibility

The capture surface uses `PKCanvasView`, `PKCanvasViewDelegate.canvasViewDrawingDidChange`, `.pencilOnly`/`.anyInput` drawing policies, `PKInkingTool(.pen)`, and `PKEraserTool(.vector)`. The vector eraser removes whole strokes. Undo/redo calls the canvas's `UndoManager`; its stacks are cleared when switching documents. The canvas uses a fixed page size and no internal zoom or scroll; the surrounding SwiftUI view allows page scrolling without changing exported coordinates.

`PKDrawing.dataRepresentation()` and `PKDrawing(data:)` preserve and reconstruct native ink. The adapter reads each stroke's `path`, `transform`, `renderBounds`, `ink`, and `randomSeed`, and each path's `creationDate` and ordered control points. It reads `PKStrokePoint.location`, `timeOffset`, `force`, `azimuth`, `altitude`, `size`, and `opacity`.

The installed 26.2 SDK does **not** expose a public `PKStroke.id`, even though [Apple's newer PKStroke documentation](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct) lists one. `randomSeed` controls rendering randomness and is not a unique identifier. This implementation keeps the existing iOS 26.2 minimum and uses only APIs present in that SDK. It does not call newer APIs dynamically or mistake an array index for identity.

V1 identity is `sha256-` plus the SHA-256 digest of the Swift JSONEncoder's sorted-key encoding of `{createdAt, points, ink, seed}`. It excludes the stroke transform and bounds. Drawing order changes and moving the stroke therefore do not change its ID. Saving and native reopening preserve IDs in the executed macOS checks. Erasing removes membership; rewriting the same shape later changes its creation time and produces a different identity. Exact duplicate strokes with identical identity inputs are rejected rather than assigned ambiguous memberships. Treat IDs as opaque strings in Python: do not reimplement Swift's floating-point JSON encoding to recreate them.

This fallback is deliberate and versioned. It is not equivalent to an operating system UUID and cannot distinguish perfect duplicate copies. When building against an SDK with supported stable stroke IDs, introduce an explicit identity strategy/migration that preserves old page mappings; do not silently reinterpret v1 IDs. No minimum OS increase is needed for this milestone.

Partial/bitmap erasing is unsupported in v1. PencilKit can retain original path samples behind a clipping mask; exporting those samples as visible ink would corrupt evaluation data. The adapter explicitly rejects masked strokes. Native data remains essential for future mask-aware schemas. The existing notebook's bitmap eraser is unchanged because notebook drawings are separate from Stroke Lab.

## Coordinate and timing conventions

A page is 1024 × 1366 PencilKit drawing points. A point is a logical drawing unit, not a screen pixel, millimetre, or guaranteed physical measurement. The origin is top-left, x increases rightward, and y increases downward. Viewport scrolling and screen scale do not enter the export. The canvas dimensions describe the intended page; they do not clip sample coordinates or guarantee every ink bound fits the page.

Ordered samples are **stroke-local PencilKit control points**, not resampled screen positions or guaranteed original hardware events. Preserve their order and their original values. Each stroke carries its own affine transform:

```text
pageX = a * localX + c * localY + tx
pageY = b * localX + d * localY + ty
```

Apply this transform exactly once before spatial grouping. Point width and height are local ink sizes; do not assume they are axis-aligned page sizes after rotation/nonuniform scaling. `bounds` is PencilKit's rendered rectangle in page space and already includes the transform and ink extent.

`createdAt` is `PKStrokePath.creationDate` expressed as Unix seconds. A point's `time` is `timeOffset`, a nonnegative number of seconds relative to its stroke path. Its approximate wall-clock time is `createdAt + time`. Point times must be nondecreasing; duplicate times are allowed. These are PencilKit timing values, not a calibrated device clock, cross-device synchronization mechanism, or proof of actual writing speed. Wall clocks can change between strokes. Never impose chronological order by sorting points or strokes; retain the native drawing order.

Force is exported unchanged as `pressure`. It is not constrained to [0,1] or assumed to be calibrated. Azimuth and altitude are radians. These properties may be synthetic for touch or test strokes. V1 does not claim a hardware identifier, Pencil model, handedness, or verified input-device provenance: PencilKit's stored drawing does not supply that evidence. Optional point metadata is omitted when absent; `null` is not a valid substitute. This adapter exports all three properties it receives.

## Grouping hierarchy and ground truth

An **expression group** is a manually chosen set of stroke IDs corresponding to one expression region for future evaluation. Its label is descriptive free text, not parsed mathematical content. A stroke belongs to at most one expression. A stroke absent from all groups is **unassigned**; there is no separate duplicated unassigned list. Empty groups are permitted so erasing the last member does not destroy an expression's identity.

A **visual row** is an optional spatial annotation *within* an expression: for example, a main writing line or a nested region. It has its own stable ID, label, members, and optional parent row. Parent references must stay within the expression, nesting must be acyclic, and every child member must belong to every ancestor. A stroke may appear in an ancestor and its child; v1 also permits overlapping rows and imposes no inferred reading order. Array order is annotation creation order. Labels such as “numerator” are human descriptions with no mathematical interpretation by the app.

**Symbol segmentation** would assign strokes or stroke fragments to characters/symbols. It is not part of expression grouping or visual rows and is not implemented. **Math IR** would describe mathematical syntax/meaning and structure such as operators, operands, fractions, or equations. It is also not implemented. No field in this contract should be treated as recognized text, LaTeX, a symbol class, or a Math IR node.

`annotations.json` carries its own version and page reference. Each mutation increments `revision` and adds an event with timestamp, author, source and action. The author is a local free-text pseudonym, not authenticated identity. The history is an audit of operations, not a full snapshot log or a mechanism for restoring past annotations. Ink undo/redo is distinct from annotation revision history.

## Field reference

All keys are case-sensitive. Unknown keys are rejected in v1; incompatible evolution requires a new version and an explicit reader/migration. Optional keys may be omitted. IDs are nonempty opaque strings.

### `strokes.json`

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Exactly `1.0.0` |
| `pageID` | Stable page UUID string, shared with annotations and the local filename |
| `coordinateSystem` | Exactly `pencilkit-points-top-left-y-down` |
| `pointSpace` | Exactly `stroke-local` |
| `timeUnit` | Exactly `seconds` |
| `creationTimeEpoch` | Exactly `unix` |
| `identityStrategy` | Exactly `sha256-path-v1`; see compatibility discussion |
| `canvasWidth`, `canvasHeight` | Positive, finite logical page dimensions |
| `strokes` | Array of strokes in native drawing order; empty pages are valid |
| `strokes[].id` | Unique stable identity within the page |
| `strokes[].createdAt` | Finite Unix seconds for path creation |
| `strokes[].points` | Nonempty array of ordered control points |
| `points[].x`, `points[].y` | Finite stroke-local coordinates |
| `points[].time` | Nonnegative relative seconds, nondecreasing within each stroke |
| `points[].pressure` | Optional finite force value |
| `points[].azimuth`, `points[].altitude` | Optional finite stylus orientation in radians |
| `points[].width`, `points[].height` | Nonnegative local sample ink size |
| `points[].opacity` | Finite sample opacity in [0,1] |
| `strokes[].transform` | Object with finite `a`, `b`, `c`, `d`, `tx`, `ty`, using the formula above |
| `strokes[].bounds` | Object with finite page-space `x`, `y`, `width`, `height`; sizes nonnegative |
| `strokes[].ink.type` | PencilKit ink type's raw string; preserve it without deriving a symbol class |
| `strokes[].ink.rgba` | Four sRGB components in [0,1], including alpha; dynamic colors resolved in light appearance |
| `strokes[].randomSeed` | Unsigned 32-bit PencilKit rendering seed; not a stroke ID |

### `annotations.json`

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Exactly `1.0.0` |
| `pageID` | Must match the raw page |
| `revision` | Nonnegative count of recorded annotation operations |
| `groups` | Array of manual expression groups |
| `groups[].id` | Unique stable expression UUID string |
| `groups[].label` | Human-readable free text; may be empty |
| `groups[].strokeIDs` | Unique references to current raw strokes; exclusive between expressions |
| `groups[].rows` | Optional-in-use hierarchy, represented as an array; empty if unused |
| `rows[].id` | Row UUID string unique across the page |
| `rows[].label` | Human-readable free text; may be empty |
| `rows[].parentRowID` | Optional reference to an ancestor row within the same expression |
| `rows[].strokeIDs` | Unique current stroke references, contained by expression and ancestors |
| `history` | Ordered mutation events; its length equals `revision` |
| `history[].number` | Sequential integer starting at 1 |
| `history[].timestamp` | Finite Unix seconds when the operation was recorded |
| `history[].author` | Nonempty local annotator pseudonym |
| `history[].source` | Exactly `manual-stroke-lab` |
| `history[].action` | Nonempty human-readable operation description |

`drawing.pkdrawing` is an opaque native `PKDrawing` serialization. Keep it together with the two JSON files; it is the recovery source for rendering, richer PencilKit features, and future export migrations. Python need not and should not try to decode this proprietary representation.

## Collection workflow

1. On an iPad running iPadOS 26.2 or later, open Folio and choose **Stroke Lab**. Start a new page. Enter an annotator pseudonym. Apple Pencil is the default input; enable **Finger drawing** explicitly for touch or simulator work.
2. Write naturally using the fixed black pen. Use **Whole-stroke eraser** to remove strokes, then switch it off to continue. **Undo ink** and **Redo ink** operate on canvas actions.
3. Turn on **Show stroke bounds** to inspect individual strokes. Tap stroke entries in the sidebar to build a multi-selection; selected bounds appear red. Selected entries show bounds, creation time and the first pressure, alongside point count and duration. Full samples are in the export. Selection currently uses the list, not a lasso or canvas hit-test.
4. Enter an expression label and choose **Create expression from selection**. Existing selected strokes move out of other expressions. Click a colored expression entry to make it active; its dot marks the destination. Rectangles around expressions use the same colors as the entries.
5. Select more strokes and choose **Assign selection to active expression**, or **Make selection unassigned**. Reassigning to the same expression preserves existing row membership.
6. To split a group, select a proper nonempty subset of its members, activate that group, and choose **Split selection from active expression**. The new expression starts with those strokes. To merge, check at least two expression checkboxes and choose **Merge checked expressions**; the first expression's identity/label survives, and all selected memberships/rows are combined.
7. For visual rows, activate an expression, select strokes from it, set a row label and optionally choose an existing **Parent row**, then add the row. Invalid memberships are rejected. Removing a row reparents its direct children to its own parent.
8. Choose **Save**. The status changes to **Saved locally**. Use **Reopen local page** to choose an existing page by UUID prefix. New/open saves a dirty page first. Leaving the screen or moving the app out of its active phase also attempts a save. Drawing and annotation changes schedule a local save after a one-second pause. Use Save before export or force-quitting, and confirm the saved status; a pending save is not crash recovery.
9. Choose **Export** to save a `.folioink` package through the system file exporter. It contains three files. Keep the package intact. Files may display it as one document; on macOS use **Show Package Contents** or access its child paths in Python.
10. Validate an exported package with `python3 scripts/validate_stroke_lab.py /path/to/page.folioink`. A successful validation checks structure and annotation references. Reopening in Folio additionally checks native/JSON fidelity.

Local pages live under the application's sandboxed `Application Support/StrokeLab/<pageID>.folioink`. No upload or recognition request is made. System device backups follow the user's OS backup settings. Choosing a cloud provider in the system export picker is an explicit user export. There is no automatic cloud synchronization.

Do not commit personal handwriting. `.gitignore` excludes `.folioink` packages, native `.pkdrawing` files, and root `handwriting-data` / `stroke-lab-data` directories. Keep extracted JSON inside one of those ignored data directories; arbitrary extracted JSON filenames elsewhere are not automatically ignored. Tests create only synthetic strokes in temporary directories, and no collected dataset is checked in.

## Python consumption and future evaluation

The included validator uses the Python standard library and the same checked-in schema. It confirms native-file presence but cannot decode/compare native PencilKit data. Future grouping evaluation should load JSON as data and apply transforms before using geometry:

```python
import json
from pathlib import Path

page = Path('/path/to/sample.folioink')
raw = json.loads((page / 'strokes.json').read_text())
annotations = json.loads((page / 'annotations.json').read_text())
by_id = {s['id']: s for s in raw['strokes']}
for group in annotations['groups']:
    ground_truth = [by_id[stroke_id] for stroke_id in group['strokeIDs']]
    # Evaluate future predicted spatial membership against these stable IDs.
for stroke in raw['strokes']:
    t = stroke['transform']
    page_points = [(t['a']*p['x'] + t['c']*p['y'] + t['tx'],
                    t['b']*p['x'] + t['d']*p['y'] + t['ty'])
                   for p in stroke['points']]
```

Retain unassigned ink when constructing evaluation sets, and choose an explicit policy for excluding or scoring it. Do not interpret rows as symbols or labels as recognized ground truth text. Dataset splits by writer/session and additional collection metadata should be designed before training, with explicit consent and schema evolution. No model training is part of this milestone.

## Verification and device checks

Run portable/native smoke checks on macOS with Xcode command-line tools:

```sh
sh scripts/check_stroke_lab.sh
```

This compiles the production contract, schema validator, exporter, and document/store implementation, generates synthetic native strokes, exercises empty/single/multiple-stroke persistence and repeated atomic replacement, annotation/row reopening, transforms, identity, point timing/pressure, split/merge/unassignment, erased membership cleanup, rewriting, and invalid-data rejection. It then validates a Swift-exported package using Python and runs seven Python regression tests. All generated files are temporary and removed by the script.

The Xcode unit suite adds nine `StrokeLabTests` covering native round-trip, full sample export fidelity, transforms, group membership after disk reopening, erasure/rewrite reconciliation, split/merge, invalid annotations and cyclic rows, schema failures, duplicate identity, mismatched native data and masks. Existing tests remain unchanged.

```sh
xcodebuild -project inkpad/inkpad.xcodeproj -scheme inkpad \
  -destination 'platform=iOS Simulator,name=<installed iPad simulator>' test
```

Execution record for this implementation:

- The macOS smoke checks executed successfully, including native PencilKit serialization and package reopening.
- Seven Python tests executed successfully; the CLI accepted a package exported by the production Swift code.
- The iOS simulator app and test targets built successfully with Xcode 26.2. In this restricted environment Swift macro subprocess sandbox creation failed by default; the build command used the compiler's `-disable-sandbox` flag via `OTHER_SWIFT_FLAGS` while the outer workspace sandbox remained active. No project build setting was changed for this workaround.
- The iOS XCTest suite was **compiled, not executed**. CoreSimulatorService is unavailable in this environment. A successful build is not evidence that the capture screen or iOS tests ran.

A physical iPad and Apple Pencil are required to verify actual Pencil capture, palm rejection, pressure/tilt samples, eraser gestures, stroke-level undo/redo, sidebar selection and boundaries while scrolling, system export UI, background saves, app termination/relaunch, and reopening real native ink without identity drift. Run a real collection session and the nine XCTest cases on device or a working simulator before treating the Lab as validated for dataset collection. Simulator finger drawing does not substitute for Pencil hardware validation.

## Known limitations

- Whole-stroke erasing only; masked/partially erased native strokes are rejected.
- Fingerprint identity cannot distinguish perfect duplicate copies. Identical identity inputs are rejected. Editing identity inputs intentionally produces a new stroke; no automatic annotation transfer is attempted.
- Erasing removes group and row references. Undoing that erasure restores ink with its original identity but does **not** restore removed annotation membership; manually reassign it. New writing remains unassigned.
- Annotation edits have revision events but no annotation undo or historical snapshot restoration. Group splits start new rows empty; surviving source rows are trimmed. Merge preserves row IDs and hierarchy.
- Fixed pen, fixed page, no import UI for external packages, no page naming/deletion, no lasso selection, no zoom, and no derived symbol/text labels. Reopening uses the local page picker. The document reader validates package contents for future import support.
- Colored rectangles are axis-aligned unions of member stroke bounds, not precise outlines. Distant members can produce a large rectangle. Colors repeat after six expressions.
- Exporting and hashing all control points on drawing changes is appropriate for small collection pages; large documents have not been performance-tested. No capture-time downsampling occurs.
- Save failures are surfaced in the Lab. Abrupt termination before an explicit or lifecycle save can lose changes; the application is not a crash-recovery recorder.
- Full sample metadata comes from stored PencilKit control points and does not prove input-device provenance or calibrated pressure.
- The app's existing deployment target and recognition/notebook features remain unchanged. No recognition quality or grouping accuracy claims are made by this milestone.
