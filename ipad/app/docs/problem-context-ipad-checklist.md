# iPad interaction guide: grouped math rows

This guide covers explicit row grouping and the first bounded contextual equation workflow. It checks that only user-selected definitions from the current problem are used.

## Before starting

1. Build and install the `inkpad` Debug app on an iPad running iOS 26.2 or later.
2. Confirm the validated local TexTeller assets have been staged if using local handwriting recognition. Recognition accuracy is not a prerequisite for the group controls: the test rows can be corrected in the review editor.
3. Use a disposable notebook or make a notebook backup before trying persistence and reopen steps.
4. Create at least three recognized rows on the same page, for example `t = 10`, `y = 2x + 11`, and `t + 6y = 15`. Accept each transcription after checking it.

## Scenarios

### Join two rows

1. Open the handwriting preview and find the first accepted row.
2. Tap **Group with another row**, then choose the second row.
3. Confirm the row reports that it is grouped with one other row.
4. Check the second row's preview; it should show the same relationship count.

Expected: only the association changes. Ink, accepted LaTeX, row order, and existing row-scoped results remain visible and intact.

### Join existing groups

1. Make a group with rows one and two.
2. From row three, group it with row two.
3. Confirm all three rows report two other rows in the group.

Expected: both previous associations become one group, without duplicate or missing rows.

### Separate one row

1. From the middle row in a three-row group, tap **Start a separate problem**.
2. Confirm that row reports no group, while the other two remain grouped.
3. Group the separated row with the third row and confirm the two become grouped.

Expected: ungrouping affects only the chosen row; joining reuses the destination group's relationship.

### Save and reopen

1. Group two rows, close the notebook, then reopen it.
2. Open the handwriting preview again and inspect both rows.

Expected: the group remains after the page is saved and reopened. If it does not, capture the app version and the exact close/reopen steps.

### Substitute and solve a grouped equation

1. Write and accept `t = 10`, `y = 2x + 11`, and `t + 6y = 15` on three rows.
2. Group the rows. Mark the first two rows as **Definition** and the final equation as **Equation to solve**.
3. In the final row, review the listed source rows, then tap **Substitute & Solve**.
4. Confirm the result is `x = -61/12` and that the explanation identifies the definitions used.
5. Change, move or ungroup a definition and check that the saved result becomes outdated.

Expected: the app uses only accepted, explicitly marked definitions from the same group that appear above the target. It rejects duplicate definitions, cycles, multiple unresolved variables, unsupported syntax and degree above two instead of guessing.

### Keep separate problems separate

1. Add a fourth row that uses `x` but belongs to a different exercise.
2. Leave it ungrouped and open its compute flow.

Expected: sharing a variable name does not create a group or introduce another row into the calculation.

## Feedback to send

Please report:

- iPad model, iPadOS version and app build/commit.
- Whether **Group with another row** and **Start a separate problem** were easy to find while writing with Pencil.
- Whether the menu listed the intended row numbers and whether row numbering was clear.
- Any association that changed unexpectedly after joining or separating rows.
- Whether group membership survived leaving and reopening the notebook.
- The recognized LaTeX and a screenshot if a row's handwriting or expression changed during grouping.
- Whether the role picker and definition source summary were clear; include the rows and intended result if the contextual solve did not match your expectation.

