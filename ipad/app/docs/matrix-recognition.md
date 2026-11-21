# Bounded matrix recognition

## Why the idle delay was insufficient

The saved iPad recognition crops showed a large matrix split into column-sized regions. The proximity segmenter only joined nearby strokes (48-point horizontal / 24-point vertical gaps). TexTeller then received incomplete matrix fragments and sometimes returned ragged rows. The four-second LINALG quiet period is still useful, but does not supply matrix structure.

## Recognition flow

1. `MatrixInkLayout` looks for tall square-bracket rails with inward hooks at both ends. Short separately drawn caps can join a rail. Compatible pairs must span multiple entry levels. Nonoverlapping inner pairs take priority.
2. `SpatialInkSegmenter` reserves the pair and its enclosed entry strokes as a single region, regardless of the normal proximity limits. Ordinary proximity cannot join this region to neighboring ink or another reserved matrix. Highlighter strokes remain excluded. All source strokes and fingerprints are preserved.
3. `StepTrackingCoordinator` consolidates previous fragment drafts into one bounded matrix draft. Bracket ownership disambiguates overlapping old fragments; unmatched old fragments become inactive. Ordinary ambiguous expression grouping remains reviewable.
4. `MatrixInkLayout` finds shared column bands, tries several glyph-scaled whitespace joins, and chooses the finest rectangular candidate within 2–6 rows and 1–6 columns. Rows are found within each column and matched by vertical order, allowing handwriting to slope across the page. Unequal occupancy or excessive vertical jumps reject the grid. Serializing the chosen cells happens only after geometry selection and only for recognition; live stroke segmentation skips cell extraction.
5. `LocalMathRecognitionService` reads each cell sequentially through the existing bundled TexTeller runtime, with cancellation checks between cells. It reconstructs one `bmatrix` draft. Empty, multiline or matrix-shaped cell predictions are rejected. Confidence stays uncalibrated (`nil`), so the user still reviews the transcription before accepting/using it. The full matrix crop remains the successful result's debug image.

Other recognition providers receive the complete bounded region through their existing services; cell inference is currently local-provider behavior. Explicit Recognize remains immediate; automatic LINALG recognition keeps the four-second inactivity delay. No drawing-store/schema migration or math operation changes were introduced.

## Limits

- The detector currently targets paired square brackets, including curved handwritten hooks. Parenthesis-delimited matrices, determinant bars, unbounded arrays and single-row vectors retain the existing recognition path. Bare bars are deliberately not reinterpreted as an ordinary matrix.
- Entries need reasonably aligned columns and visible gaps. Touching entries, very uneven spacing, fractions with stacked components, augmented separator bars, nested matrices and ambiguous grids are not established as supported. Geometry is a heuristic: it can still choose the wrong dimensions. Always verify the displayed dimensions and entries.
- Blank/missing cells are never filled with zero. A detected matrix with an unclear or oversized grid returns a review-oriented error rather than manufacturing a rectangular answer.
- Entry inference costs one model call per cell, so a 5×6 matrix takes substantially longer than one expression. New writing cancels the old request; a fresh idle period restarts it. Timing on the iPad must be measured independently of the Mac diagnostic run.
- Matrix arithmetic retains the existing numeric-entry and operation-size restrictions. Recognizing symbolic LaTeX does not establish support for symbolic matrix computation.

## Device check and feedback

1. Use local recognition, automatic detection on, and LINALG. Write a complete square-bracketed 2×2 matrix, then a 5×6 matrix. Pause four seconds. Expect one recognition region and one rectangular matrix draft for each.
2. Repeat with negative and multi-digit entries (`-17`, `-24`, `35`). Verify every sign and digit, especially where a minus sign is spaced away from its number.
3. Reopen the previously fragmented matrix and tap **Recognize** to force a retry. Expect the old pieces to consolidate. Review and accept only after the full transcription is correct.
4. Write two separately bracketed matrices and an equation nearby. Confirm they remain independent regions. Inspect boundaries before accepting either matrix.
5. Leave a cell blank, omit a bracket, use touching entries, and try an augmented matrix. Record which cases request review versus use the fallback path; these are not acceptance examples for general matrix recognition.
6. Edit/erase a cell during recognition; an old result must not publish as current. Verify acceptance invalidates and dependent results become outdated. Reopen the page and confirm the original ink survives.

Send the handwritten matrix and recognized draft, expected/actual dimensions, first wrong cell as `(row, column)`, and time from Pencil lift to draft. This separates bounds/grid errors from individual model recognition errors.

No automated test cases or fixtures were added: repository test development remains paused. See the checkpoint record for the exact builds, existing suites and real-ink diagnostic execution performed for this increment.
