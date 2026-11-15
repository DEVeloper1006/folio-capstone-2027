# Canvas ink tools and inserted results

## Controls

Tap Pen, Highlighter or Eraser to select it and open a nonmodal thickness panel. Start writing outside the panel to close it
without losing the first stroke, or tap Done. Widths
are independent, use PencilKit's supported ranges, and are remembered with the
chosen ink colour. Lasso selects strokes and has no thickness setting. Circle the ink or touch and
hold a stroke to select it, then drag the selection. The panel also provides
Draw with finger; Pencil input is always supported. The input preference is
explicit and consistent across simulator and device builds. The black
swatch is true black; the colour well opens the system colour picker for arbitrary
opaque RGB colours. Highlighter opacity remains translucent. The native canvas
uses light appearance against the notebook's light paper, including when the
iPad uses dark mode. Existing stroke data is preserved rather than recoloured.

Undo and Redo operate on the native canvas undo manager, shared with result
insertion, movement and removal. Pen/highlighter strokes, erasures and native
lasso edits use PencilKit's own undo actions. Result moves register one action
after the drag completes; intermediate drag positions do not save repeatedly.
Undo history is session-local (up to 100 actions); saved drawings and placements
survive relaunch, but the in-memory undo history does not.

## Results on the page

Compute an integral, then use **Insert result** in its preview card. The preview
closes and focuses the inserted result on the page. Drag the result object directly with a finger or Apple Pencil, with any tool
selected. Only result rectangles intercept touches; blank areas always reach
PencilKit for writing, erasing or native ink selection. Its close control removes it from the page while preserving
the computed result in the preview for reinsertion. **Show on page** focuses an
already-inserted result without making duplicates. Removing the result from the
preview also removes the page object; Undo can restore it during that session.

Result objects remain separate from PencilKit strokes and are not included in
handwriting recognition. They retain the original computation's source revision
and are labeled outdated when that source changes. Outdated results cannot be
newly inserted as current answers. Scroll/zoom transformations are applied from
logical page coordinates, and positions are persisted. The initial object size
is fixed; resizing and arbitrary rotation are not part of this iteration.

MathJax renders locally into a PDF-backed cached PNG so moving a result does not
run a new web view or computation on each frame. There is no server request. The
placement metadata and cached image extend ComputationResult additively. PNG/PDF
page exports include inserted result objects and their outdated labels.

## Implementation

- CanvasView/CanvasViewModel bind an explicit native undo manager, refresh its
  action availability, attach Pencil double-tap interaction, synchronize actual
  tool widths/colour, report viewport changes, and persist tool preferences.
- ToolStripView provides nonmodal per-tool panels and the system ColorPicker.
- PencilKit exclusively owns live ink, erasure and selection; SwiftUI refreshes
  never reassign a drawing snapshot or disable the native canvas during a drag.
- Pencil double-tap respects the system preference; switching back from eraser
  restores the previous ink tool rather than always choosing pen.
- CanvasResultStore saves undoable placement state. It places new results beneath
  the source while avoiding existing handwriting regions and other result boxes.
- ResultImageRenderer uses bundled MathJax and WebKit PDF output. PDF rendering
  avoids blank snapshots from occluded web views. The cached image remains local.
- CanvasResultLayer presents the objects in page coordinates and records one
  persisted move at the end of each drag. The notebook's canvas is constrained to
  its visible viewport, with a separately scrolling page and aligned paper grid.

## Checkpoint and recovery

The latest repair checkpoint is `.reports/canvas-repair-20261105-145656/`
in folio-ipad-labs. It preserves the pre-repair dirty source, the signed
working rollback app, and a current iPad database backup. The earlier canvas
checkpoint `.reports/canvas-tools-20261105-131506/` remains intact. Guarded apply/rollback scripts validate hashes before writing and
refuse to overwrite later edits. Source rollback does not automatically undo a
SwiftData migration or restore older device data; database restoration is a
separate explicit recovery action because it would replace newer notebook edits.

Verification logs and device evidence are retained in the checkpoint. The result
computation/recognition models are unchanged by these canvas changes.

## Validation boundaries

The repair adds actual erasure/undo/redo and native lasso select/move/undo UI
checks, drawing while tool controls are open, and drawing after result moves.
Debug accessibility fingerprints use rendered ink rather than serialized
PKDrawing bytes: native undo can serialize the same ink differently. Erasure
checks wait for PencilKit's asynchronous drawing-changed callback.

Simulator UI tests use synthesized finger gestures. Physical UI tests also
synthesize touch input; they do not simulate a real Apple Pencil. A real Pencil
check remains a separate user validation. Recognition tests use deterministic
fixtures; this canvas repair does not establish model accuracy. Exact results
and device verification are recorded in the checkpoint README and evidence.

## Empty-page regression

PencilKit returns CGRect.null for an empty or fully erased drawing. Its maxY is
not a valid page height. CanvasViewModel.contentHeight explicitly rejects null,
empty and non-finite bounds and always returns at least 2048 points. Both native
scroll content size and notebook/export sizing use finite values. Otherwise a
new page, or erasing the final stroke, can leave an infinite scroll surface that
will not accept new ink. Tests include an initially empty page, erase-all then
draw-again, and library navigation into an empty notebook.

The failure was reproduced on an independent copy of the existing notebook
store before the fix; the same reproduction passed after the fix. Private
notebook-copy diagnostics are retained in the checkpoint, not required by the
normal test suite. PDF thumbnail generation also keeps its PDFDocument alive
for the complete render; diagnostic ink hashing runs only in UI-test launches.

The computation workbench refinement uses natural result-image scale and
adaptive sizes for newly inserted cards. See computation-workbench.md. Finger
and Pencil dragging no longer require Lasso; Lasso remains the native tool for
selecting and moving handwriting. Canvas and exports share the sizing helper.

Tool settings now open only when the already-selected tool is tapped again.
The latest result cache uses explicit pixel-scale rasterization and tight
foreground cropping; cached old cards refresh automatically. See
computation-workbench.md for the algebra update and current limits.
