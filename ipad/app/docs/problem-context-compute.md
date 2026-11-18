# Problem grouping and contextual computation

## Current implementation boundary

The iPad notebook persists handwritten expression rows as `Step` models. Each row keeps its ink, recognition draft, accepted transcription, revisions and row-scoped computation results. `Step.problemGroupID` adds an optional, user-controlled association between rows on the same page. It does not change the ink segmentation region: one row still means one expression-recognition input.

In the handwriting preview, use **Group with another row** to connect rows. If either row already belongs to a group, the action joins both groups. **Start a separate problem** removes only the current row; the remaining rows retain their association. The relation is saved with the page. Rows without a group remain independent.

For each grouped row, select **Definition** or **Equation to solve** in **Use this row as**. Folio uses only accepted definitions that appear above the selected equation in the same group. The contextual **Substitute & Solve** action shows which definitions it will use, then calls the existing native linear/quadratic polynomial solver. The result stores a manifest of every active row in the problem group, including each row's stable ID, accepted transcription/revision, ink fingerprint, meaning, group and position. Editing, adding, reordering, reclassifying or ungrouping a row makes the result outdated.

This first contextual solver accepts the existing bounded polynomial grammar (rational/decimal constants, one-letter symbols, arithmetic, parentheses, fractions and integer powers 0–20), and requires at most one unresolved variable after substitution. The final equation must be degree two or lower. Definitions must be explicitly selected, have one variable on the left, occur earlier than the target and avoid duplicate/circular dependencies. Function definitions, arbitrary MathJSON operations, multiple unknowns, inequalities, matrices and unsupported syntax remain outside this path. A shared group does not imply mathematical correctness.

## Existing math services and parser boundary

The web client has `client/src/math/latex-ast.ts`, which uses the pinned Cortex Compute Engine to parse LaTeX into MathJSON. This is the existing structured-expression prototype to study when designing a portable AST contract. The older research workspace includes a bounded MathJSON-to-SymPy interpreter. Neither is the active iPad computation runtime.

The iPad continues to use its native bounded math services and the existing local calculus adapter. The new context path parses mixed-symbol expressions into the existing polynomial AST, substitutes explicit definitions, then sends the resulting one-variable equation to the existing solver. The example `t = 10`, `y = 2x + 11`, `t + 6y = 15` is supported within those constraints. This does not make the whole row grammar general-purpose: existing operation coverage remains as documented in `calc1-support.md`, `exact-algebra.md`, and `math-coverage-roadmap.md`.

## Next implementation stages

1. **AST and semantic classification (implemented, bounded):** the iPad reuses its native polynomial AST. A per-row picker records the user's choice between definition and constraint; function definitions and general equality inference are not implemented.
2. **Problem-local symbol environment (implemented, bounded):** resolve explicitly marked earlier single-symbol definitions only inside the selected row's group. Duplicate definitions and dependency cycles are rejected. Results retain a manifest of the full group and become outdated after a source, group, role or ordering change.
3. **Contextual operation (implemented, bounded):** show the target row's supported **Substitute & Solve** action only when a one-variable, degree-two-or-lower answer can be computed, and list the definition rows used.
4. **Broader operation planning (future):** generalize context actions after extending and reviewing the AST grammar. Never silently include rows from another group.
5. **Compact alternative-operation menu (future):** the current contextual action lives in the grouped row preview, while the existing general compute workbench remains. Simplify its operation selection after observing the first workflow on iPad; keep advanced parameters available.

Do not replace PencilKit, row recognition, SwiftData notebook relationships, or native math services as part of these stages. Schema changes need a migration and reopen check. Each stage should have a rollback point and a documented list of supported forms before it is described as complete.

## Data and provenance rules

- A group is page-local; it does not carry definitions to another page.
- Only a row the user explicitly marks as a definition may enter the symbol environment; ambiguous equalities are not auto-classified.
- Recognition acceptance confirms the transcription only, not mathematical correctness.
- A result that uses multiple rows must record every source row's stable ID, accepted LaTeX, accepted revision number and fingerprint, plus group and order.
- A changed or ungrouped source invalidates any result depending on it; unrelated row results remain current.
- Preserve the original strokes when recognition is edited or a group changes.
- Keep matrices and multiline recognition inputs distinct from a group of independent rows.
- If syntax is unsupported or intent is ambiguous, ask for correction or an explicit choice; do not coerce it into another operation.

