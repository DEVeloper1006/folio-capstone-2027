# Problem grouping and contextual computation

## Current implementation boundary

The iPad notebook persists handwritten expression rows as `Step` models. Each row keeps its ink, recognition draft, accepted transcription, revisions and row-scoped computation results. `Step.problemGroupID` adds an optional, user-controlled association between rows on the same page. It does not change the ink segmentation region: one row still means one expression-recognition input.

In the handwriting preview, use **Group with another row** to connect two rows. If either row already belongs to a group, the action joins both groups. **Start a separate problem** removes only the current row; the remaining rows retain their association. The relation is saved with the page. Rows without a group remain independent.

Grouping currently records student intent. It does not yet change the computation workbench's source scope, discover definitions, substitute values, or solve a system across rows. A shared group is not proof that its expressions are semantically compatible.

## Existing math services and parser boundary

The web client has `client/src/math/latex-ast.ts`, which uses the pinned Cortex Compute Engine to parse LaTeX into MathJSON. This is the existing structured-expression prototype to study when designing a portable AST contract. The older research workspace includes a bounded MathJSON-to-SymPy interpreter. Neither is the active iPad computation runtime.

The iPad continues to use its native bounded math services and the existing local calculus adapter. Native polynomial parsing currently models one polynomial variable; it cannot faithfully interpret the motivating mixed-symbol context `t = 10`, `y = 2x + 11`, `t + 6y = 15` as a shared problem. The app must not claim that a row group enables this substitution yet. Existing operation support remains exactly as documented in `calc1-support.md`, `exact-algebra.md`, and `math-coverage-roadmap.md`.

## Next implementation stages

1. **AST and semantic classification:** parse accepted transcriptions into a bounded common expression representation; distinguish definitions, function definitions, constraints and derivation steps. Keep ambiguous equalities unresolved until the user chooses their meaning.
2. **Problem-local symbol/function store:** resolve definitions only inside one explicit group, preserve source row IDs and accepted revision fingerprints, detect duplicate definitions and dependency cycles, and mark dependent outputs stale when an input changes.
3. **Contextual operation plan:** derive eligible operations from the selected target and resolved bindings. Show the target, included definitions, unresolved variables and required extra inputs before computation. Never silently include a row from another group.
4. **Substitute and solve:** use the AST representation to substitute supported definitions into a target equation, then call an existing solver only when its bounded grammar accepts the result. Preserve a trace of substitutions and every source revision used.
5. **Compute menu:** make the suggested contextual action the primary action and expose alternatives in a compact operation menu. Keep topic browsing and advanced parameters available without inserting another generic selection screen into the common path.

Do not replace PencilKit, row recognition, SwiftData notebook relationships, or native math services as part of these stages. Schema changes need a migration and reopen check. Each stage should have a rollback point and a documented list of supported forms before it is described as complete.

## Data and provenance rules

- A group is page-local; it does not carry definitions to another page.
- Recognition acceptance confirms the transcription only, not mathematical correctness.
- A result that uses multiple rows must record every source row's stable ID, accepted LaTeX, accepted revision number and fingerprint.
- A changed or ungrouped source invalidates any result depending on it; unrelated row results remain current.
- Preserve the original strokes when recognition is edited or a group changes.
- Keep matrices and multiline recognition inputs distinct from a group of independent rows.
- If syntax is unsupported or intent is ambiguous, ask for correction or an explicit choice; do not coerce it into another operation.

