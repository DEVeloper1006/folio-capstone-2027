# Folio: first iPad handwriting capture session

Use an iPad and Apple Pencil. This worksheet collects ink and manual expression memberships; Folio does not recognize or solve these expressions yet. The first session is a small baseline, not a training dataset or evidence of recognition accuracy.

## 1. Install and check the app

1. Connect/unlock your iPad and open `inkpad/inkpad.xcodeproj` in Xcode on your Mac. Use the `stroke-capture-ipad-workflow` branch.
2. Select the **inkpad** scheme and your iPad as the run destination. The current target requires **iPadOS 26.2 or later**. Use your development team under Signing & Capabilities if Xcode requests signing setup. Follow any pairing/trust or Developer Mode prompts shown by Xcode/iPad.
3. Run the app, open **Folio → Stroke Lab**, and use landscape orientation. Keep **Finger drawing off** for Apple Pencil capture. Scroll the page with your finger when necessary.
4. Enter a pseudonym such as `writer-01` under Annotator. Use the same pseudonym for this session; re-enter it after relaunch if needed. Avoid your full name or other personal information in the ink.
5. Make a disposable test page: write `x + 2 = 5`, test the whole-stroke eraser, and undo/redo. Turn the eraser off again. Check **Show stroke bounds** and ensure bounds track the ink.
6. Click **Select unassigned strokes**, label the group `CHECK-01`, and choose **Create expression from selection**. Confirm the colored boundary surrounds the equation and unassigned count is zero.
7. Click **Save**, note the page UUID shown in the sidebar, leave Stroke Lab, reopen it, and use **Reopen local page** to open that UUID prefix. Check both the ink and group. Then relaunch the app and repeat the check. A fresh screen may be blank until you choose the saved page.
8. Export this test page and validate it on the Mac using the command below. If drawing, erasing, reopening, or export fails, stop here and report the behavior before doing the collection pages.

## 2. How to capture each worksheet item

Choose **New** before each page below. You will create **four collection pages**, with six expression groups on each page. The disposable `CHECK-01` page is separate.

For every numbered item, in order:

1. Write only the displayed equation/expression with Apple Pencil. Write real superscripts, fraction bars, roots, and integral limits; do not copy Markdown/LaTeX commands as text. Use normal handwriting and comfortable size, leaving space between items. Do not write the item ID, title, or explanatory text on the canvas.
2. Tap **Select unassigned strokes**. Visually confirm the selected red stroke boxes cover only this item. This shortcut deliberately selects *all* currently unassigned ink; manually deselect stray strokes if necessary.
3. Type the exact item ID, such as `P01-E01`, in **Expression label**, then tap **Create expression from selection**. This is a manual grouping instruction from you; no mathematical meaning is inferred.
4. Check that the new colored boundary encloses the whole item and that unassigned count is zero. The next shortcut replaces the old selection, so you do not need to clear it between items.
5. Pause for local autosave or press **Save**. Check that the status says saved rather than unsaved or showing an error.

Copy the supplied expressions first. Do not add solution steps to pages 1–3; page 4 deliberately captures a small worked solution. Write naturally, with your usual stroke order. Do not artificially make every pen-down stroke a complete symbol, and do not trace over an equation to make it prettier. If you make a genuine mistake, use the eraser and correct it. If you erase or undo after annotating, inspect group membership again: ink undo does not restore removed annotations.

Use a fresh page if you run out of space. Preserve the same item IDs and record an extra page UUID in the manifest. Do not squeeze strokes down just to fit six entries.

### Page 1 — basic equations

| Order | Exact expression label | Write |
| --- | --- | --- |
| 1 | `P01-E01` | $x + 2 = 5$ |
| 2 | `P01-E02` | $3x - 7 = 11$ |
| 3 | `P01-E03` | $2(x + 3) = 14$ |
| 4 | `P01-E04` | $4a + 3b = 12$ |
| 5 | `P01-E05` | $y = -2x + 5$ |
| 6 | `P01-E06` | $0.5x + 1.25 = 3.75$ |

Save, export, and record the page UUID before choosing New.

### Page 2 — vertical structure and superscripts

Write fractions vertically with a horizontal bar. Keep all parts of each item in one expression group.

| Order | Exact expression label | Write |
| --- | --- | --- |
| 7 | `P02-E01` | $\frac{x}{2} + 3 = 7$ |
| 8 | `P02-E02` | $\frac{x + 1}{x - 2} = 3$ |
| 9 | `P02-E03` | $x^2 + 5x + 6 = 0$ |
| 10 | `P02-E04` | $a^2 + b^2 = c^2$ |
| 11 | `P02-E05` | $\sqrt{x + 4} = 3$ |
| 12 | `P02-E06` | $\frac{1}{1 + \frac{1}{x}} = \frac{x}{x + 1}$ |

Optional row practice for `P02-E02`: activate that expression, clear the selection, and select only the numerator's strokes to add a top-level row labeled `numerator`. Add another top-level row labeled `denominator` for the denominator's strokes. Leave the fraction bar and `= 3` outside these rows but inside the expression. Skip row annotation if selection is difficult; expression membership is the priority.

Save, export, and record the page UUID before choosing New.

### Page 3 — varied mathematical notation

These are expressions to copy, not problems you must solve. Subscripts go below the writing line; integral/summation limits go in their usual positions.

| Order | Exact expression label | Write |
| --- | --- | --- |
| 13 | `P03-E01` | $x_1 + x_2 = 10$ |
| 14 | `P03-E02` | $\sin(\theta) = \frac{1}{2}$ |
| 15 | `P03-E03` | $\log_2(8) = 3$ |
| 16 | `P03-E04` | $\frac{d}{dx}(x^3) = 3x^2$ |
| 17 | `P03-E05` | $\int_0^1 x^2\,dx = \frac{1}{3}$ |
| 18 | `P03-E06` | $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ |

Save, export, and record the page UUID before choosing New.

### Page 4 — worked steps and neighboring expressions

Write these six lines top to bottom, with normal solution-line spacing. Group **each line separately**, immediately after writing it. Lines 1–4 form one worked solution; lines 5–6 are two neighboring equations of a small system. Do not merge all six into one group.

| Order | Exact expression label | Write |
| --- | --- | --- |
| 19 | `P04-E01` | $2(x + 3) = 14$ |
| 20 | `P04-E02` | $2x + 6 = 14$ |
| 21 | `P04-E03` | $2x = 8$ |
| 22 | `P04-E04` | $x = 4$ |
| 23 | `P04-E05` | $x + y = 5$ |
| 24 | `P04-E06` | $x - y = 1$ |

Save and export. Do not collect many repetitions yet. First we should inspect these pages for real stroke fidelity, correct annotation references, and usable boundaries.

## 3. Where the data is

**Save / autosave:** inside Folio's private application sandbox on your iPad:

```text
<Application container>/Library/Application Support/StrokeLab/<page UUID>.folioink/
    drawing.pkdrawing
    strokes.json
    annotations.json
```

The leading application-container path is assigned by iPadOS and can change. This private location is not a normal visible folder in Files, and plugging the iPad into the Mac does not automatically copy it into this repository. Reopen these copies through Stroke Lab's **Reopen local page** menu. Do not delete/reinstall the app until you have exported and verified your pages; deleting the app can remove its local data.

**Export:** choose **Export** in Stroke Lab, then choose a destination in the system Files picker. This creates a separate `.folioink` copy where **you** select. You can save to an available local Files folder, then transfer through Files/AirDrop to the Mac, or explicitly choose iCloud Drive if you want that transfer route. Local saving itself does not upload data. Re-export after annotation changes; an old exported copy does not update itself.

The export filename defaults to the page UUID shown in the sidebar. Record it in the manifest below. A `.folioink` package may appear as a single document; on macOS you can use **Show Package Contents**. Keep its three files together. Python reads JSON directly; `drawing.pkdrawing` preserves the native ink.

On your Mac, create this folder inside the repository for the transferred packages:

```text
/Users/jasimraza/Desktop/capstone/ink-pad/handwriting-data/session-01/
```

This is an ignored local data directory, not a tracked dataset. The app does not create or populate this Mac folder automatically. Put your exported `.folioink` packages there after transfer. Keep the UUID filenames, and keep a copy of the manifest alongside them. A screenshot alone is not a stroke-data export.

## 4. Validate and tell me what to inspect

From a Terminal on the Mac:

```sh
cd /Users/jasimraza/Desktop/capstone/ink-pad
mkdir -p handwriting-data/session-01
# Transfer your exported packages into this directory, then substitute a real filename:
python3 scripts/validate_stroke_lab.py handwriting-data/session-01/PAGE-UUID.folioink
```

Run that last command once for each package, replacing `PAGE-UUID` with its actual name. Validation should report the number of strokes and expressions. Each complete worksheet page should have **six expressions**, with a variable stroke count. Do not manually edit the JSON to make validation pass. The validator checks the shared schema and memberships; reopening in Folio additionally checks native/portable consistency.

Copy this table to `handwriting-data/session-01/collection-notes.md` and fill it in. Do not put personal samples or filled-in collection notes in the tracked docs folder.

| Worksheet page | Actual page UUID / exported filename | Groups | Reopened correctly? | Validator result | Notes |
| --- | --- | --- | --- | --- | --- |
| Disposable CHECK | | 1 | | | |
| Page 1 | | 6 | | | |
| Page 2 | | 6 | | | |
| Page 3 | | 6 | | | |
| Page 4 | | 6 | | | |

When ready, tell me: **“The packages are in `ink-pad/handwriting-data/session-01`; inspect them.”** I can then validate the actual exports, check group labels against this worksheet, inspect timing/pressure and transformed geometry, and identify capture problems before we plan further collection or grouping evaluation. No training or recognition implementation is needed for this checkpoint.
