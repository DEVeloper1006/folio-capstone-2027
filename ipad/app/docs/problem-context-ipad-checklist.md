# iPad interaction guide: automatic problem context

Use a disposable notebook. The installed build must include compiled `Encoder.mlmodelc`, `Decoder.mlmodelc`, `tokenizer-table.json` and `model-manifest.json`; see `../../README.md` for model staging. No grouping or role setup is required.

## Main workflow

1. Write nearby separate rows: `t = 10`, `y = 2x + 11`, `t + 6y = 15`.
2. Recognize the handwriting. Correct misread text and accept the three transcriptions.
3. Open the final row preview. Confirm **Detected problem** lists the intended rows and **Using** lists the definitions above.
4. Tap **Verify & Solve**. Expect `x = -61/12` and an explanation naming the source rows.
5. Edit a definition; the old answer must become outdated. Correct and accept the new transcription before recomputing.
6. Reopen the notebook and confirm context is still detected, source summaries are correct, and unchanged answers remain current.

## Corrections and boundaries

- Write an unrelated exercise farther down the page or in another column. It must not inherit the previous problem's definitions.
- Put text or unsupported notation between two exercises. Context must stop at that row.
- If nearby exercises are incorrectly joined, choose **Wrong problem? → Separate here** on the first row of the second exercise. Reopen the notebook and confirm the correction persists. **Use automatic context** removes it.
- Leave a needed definition unaccepted. The target must explain that the definition needs review and must not compute using its draft.
- Edit target text without accepting it. The contextual solve action must be disabled until acceptance.
- Try a new definition of the same symbol. It should start a fresh inferred scope rather than overwrite the earlier exercise silently.
- Try circular definitions, multiple unresolved variables and an equation above degree two. No unsupported result should be saved; source ink and editable transcriptions must remain.
- Confirm writing, erasing, lasso, undo, insertion, result movement and notebook reopening still work.

## Feedback to send

- Which step first required unexpected effort?
- Did **Detected problem** include precisely the rows you intended? Include their transcriptions and a screenshot for wrong grouping.
- Did the **Using** summary make the substitution clear before solving?
- Was **Separate here** sufficient to correct a mistake, and did it survive reopening?
- Include the iPad model, OS version, build/commit and expected versus actual result.

The new automatic-group workflow needs direct device verification. Passing existing tests for adjacent workflows does not establish its interaction correctness.
