# Problem grouping and contextual computation

## Current implementation boundary

The iPad notebook persists handwritten expression rows as `Step` models. Each row keeps its ink, recognition draft, accepted transcription, revisions and row-scoped computation results. `Step.problemGroupID` adds an optional, user-controlled association between rows on the same page. It does not change the ink segmentation region: one row still means one expression-recognition input.

Folio now infers problem context automatically after recognition, transcription acceptance and preview reopening. The normal flow is **review handwriting → verify the detected definitions → solve**. No grouping menu or per-row role picker is required. The target preview shows the detected row numbers and the exact definitions used, followed by **Verify & Solve**. Edited but unaccepted target text cannot compute; each used definition must also have an accepted transcription.

`Step.problemASTJSON` caches a Codable statement containing the input text and native left/right ASTs. The cache is reused only for the exact current accepted transcription (or recognition draft before acceptance). The inference service walks active rows in page order, records `problemIntentRaw` and `problemGroupID`, and treats a single-symbol left side that does not reference itself on the right as a candidate definition. A group ID is the stable ID of its first row, so refreshing unchanged context does not invalidate results.

Scopes stop at unread/unsupported rows, large vertical gaps (greater than max(96 points, twice the larger adjacent row height)), different columns (horizontal intervals separated by more than 80 points), repeated definition names, a new definition after a target equation, page boundaries or a saved **Separate here** correction. These are deterministic heuristics, not proof that rows belong to one exercise. Nearby unrelated equations can still be inferred together, so the source summary is part of verification. **Wrong problem? → Separate here** records `problemStartsNewScope`; **Use automatic context** removes that correction. Changing old manual groups is expected: the new inference replaces those associations when the notebook preview opens.

The solver follows symbol dependencies through earlier definitions in the same scope. It accepts rational/decimal constants, one-letter symbols, arithmetic, parentheses, fractions and integer powers 0–20, at most one unresolved variable after substitution and final degree at most two. Duplicate/circular dependencies and unsupported notation remain rejected. General MathJSON operations, function definitions, inequalities, matrices and multi-unknown systems are outside this path.

Every contextual result stores a full group manifest with stable row IDs, acceptance state, accepted revisions/transcriptions, ink fingerprints, inferred meaning and position. Source edits or scope changes make the old result outdated. Cache/schema additions are optional SwiftData fields; successful compile is not proof of migration on every historic notebook store.

## Existing math services and parser boundary

The web client has `client/src/math/latex-ast.ts`, which uses the pinned Cortex Compute Engine to parse LaTeX into MathJSON. This is the existing structured-expression prototype to study when designing a portable AST contract. The older research workspace includes a bounded MathJSON-to-SymPy interpreter. Neither is the active iPad computation runtime.

The iPad continues to use its native bounded math services and the existing local calculus adapter. The new context path parses mixed-symbol expressions into the existing polynomial AST, substitutes explicit definitions, then sends the resulting one-variable equation to the existing solver. The example `t = 10`, `y = 2x + 11`, `t + 6y = 15` is supported within those constraints. This does not make the whole row grammar general-purpose: existing operation coverage remains as documented in `calc1-support.md`, `exact-algebra.md`, and `math-coverage-roadmap.md`.

## Follow-on work

- Extend semantic interpretation beyond the bounded polynomial AST, including function stores, after defining their execution and provenance contract.
- Collect device feedback on automatic scope boundaries and provide richer corrections if the simple separation control is insufficient.
- Simplify the general alternative-operation workbench; contextual solve already uses the direct verification path.

Do not replace PencilKit, row recognition, SwiftData notebook relationships, or native math services as part of these stages. Schema changes need a migration and reopen check. Each stage should have a rollback point and a documented list of supported forms before it is described as complete.

## Data and provenance rules

- A group is page-local; it does not carry definitions to another page.
- Candidate definitions are inferred from AST equality structure. Display used definitions for verification; unsupported syntax never enters the symbol environment.
- Recognition acceptance confirms the transcription only, not mathematical correctness.
- A result that uses multiple rows must record every source row's stable ID, accepted LaTeX, accepted revision number and fingerprint, plus group and order.
- A changed or ungrouped source invalidates any result depending on it; unrelated row results remain current.
- Preserve the original strokes when recognition is edited or a group changes.
- Keep matrices and multiline recognition inputs distinct from a group of independent rows.
- If syntax is unsupported or intent is ambiguous, ask for correction or an explicit choice; do not coerce it into another operation.

