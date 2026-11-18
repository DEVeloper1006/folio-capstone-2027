# Folio major-version regression checklist: math context

Add confirmed cases here as grouping, AST interpretation and cross-row computation gain support. Keep unsupported workflows clearly marked until implementation and validation exist. Do not add or extend automated test code while the repository's test-development pause is active.

## Notebook and recognition invariants

- [ ] Write, erase, select, undo and redo PencilKit ink; confirm the notebook still saves and reopens.
- [ ] Recognize and accept one expression; acceptance confirms transcription only and does not mark mathematics correct.
- [ ] Correct a transcription and accept it; original ink remains available.
- [ ] Change ink after acceptance; stale acceptance and row results are invalidated as before.
- [ ] Two adjacent independent rows remain separate recognition inputs; fractions, exponents and matrices remain representable.
- [ ] Recognition without staged local model assets gives the documented setup failure; a build alone is not evidence of handwriting accuracy.

## Explicit problem grouping (implemented increment)

- [ ] Group two rows from the recognition preview; both rows show the relationship.
- [ ] Join two existing groups; all intended members share one group.
- [ ] Remove one row from a group; only that row becomes independent.
- [ ] Remove a middle row; remaining group members stay together.
- [ ] Save and reopen the page; group IDs persist.
- [ ] Same variable in unrelated rows does not automatically group them.
- [ ] Grouping does not alter ink, accepted transcription, row order or current row-scoped computation source.
- [ ] Empty/single-row pages provide no invalid group action.

## AST and semantic analysis

- [ ] Future expansion: parse all supported numbers, symbols, arithmetic precedence, implicit multiplication, fractions, powers, roots, parentheses and relations into a portable stable AST/MathJSON. The current iPad path only accepts its documented bounded polynomial grammar.
- [ ] Require the user to mark each grouped row as a definition or target equation; never infer those roles from equality alone.
- [ ] Parse `t = 10`, `y = 2x + 11`, and target `t + 6y = 15` into bounded native ASTs and show the selected definitions before calculation.
- [ ] Preserve unknown symbols; do not label prose or undeclared function calls as math without evidence.
- [ ] Reject unsupported syntax with a localized message and preserve source ink/transcription.
- [ ] Future expansion: round-trip supported AST to displayed math without changing grouping or relation semantics.

## Problem-local definitions and contextual solving

- [ ] In one explicit group, mark `t = 10` and `y = 2x + 11` as definitions and target `t + 6y = 15` as the equation; confirm the contextual action returns `x = -61/12` (manual device case still pending).
- [ ] Verify the result records every used definition's row ID, accepted revision, fingerprint, group and position.
- [ ] Adding, deleting, reordering or reclassifying any active row in the group makes an existing contextual result outdated.
- [ ] Ensure definitions from another group or page are never inherited.
- [ ] Detect duplicate/conflicting definitions and dependency cycles; ask the user to resolve them.
- [ ] Reject multiple unresolved variables, degree above two and unsupported syntax with a clear recoverable message.
- [ ] Changing or removing any contributing definition marks dependent results stale.
- [ ] Record every source row and accepted revision/fingerprint used by a contextual result.
- [ ] Keep unsupported equations, multiple unknowns and unsupported functions out of the linear/quadratic solver; do not approximate silently.

## Compute interface and existing service regression

- [ ] Future UI work: evaluate and simplify the general compute workbench's operation menu after collecting iPad feedback; retain access to existing advanced operation choices.

- [ ] Inline suggestion starts with the accepted source row and asks only for required inputs.
- [ ] Changing operation, variable or bounds refreshes review and does not retain a stale answer.
- [ ] Compute can be cancelled; the cancelled request cannot overwrite a newer result.
- [ ] Results remain row-scoped until explicit reuse is chosen.
- [ ] Result insertion, movement, removal and notebook reopen continue to work.
- [ ] Keep unsupported integral, symbolic matrix, proof, hint and tutoring behavior clearly bounded; do not imply MockMathEngine actions are verified computation.
- [ ] Verify supported arithmetic, polynomial, equation, calculus and numeric matrix examples listed in the app's coverage docs.

