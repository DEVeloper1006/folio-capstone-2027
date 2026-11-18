# Folio major-version regression checklist: math context

Add confirmed cases here as grouping, AST interpretation and cross-row computation gain support. Keep unsupported workflows clearly marked until implementation and validation exist. Do not add or extend automated test code while the repository's test-development pause is active.

## Notebook and recognition invariants

- [ ] Write, erase, select, undo and redo PencilKit ink; confirm the notebook still saves and reopens.
- [ ] Recognize and accept one expression; acceptance confirms transcription only and does not mark mathematics correct.
- [ ] Correct a transcription and accept it; original ink remains available.
- [ ] Change ink after acceptance; stale acceptance and row results are invalidated as before.
- [ ] Two adjacent independent rows remain separate recognition inputs; fractions, exponents and matrices remain representable.
- [ ] Recognition without staged local model assets gives the documented setup failure; a build alone is not evidence of handwriting accuracy.

## Automatic problem grouping

- [ ] Nearby definitions and a dependent target automatically share one scope after recognition; no setup menu appears.
- [ ] The preview shows detected source rows and only offers verification/solve for supported context.
- [ ] Text, unread rows, large gaps, column boundaries and page boundaries stop context.
- [ ] Repeated definition names and definitions after a target start fresh scopes.
- [ ] **Separate here** corrects a wrong inference and survives reopen; **Use automatic context** removes the override.
- [ ] Reopening unchanged context retains stable group IDs and current result manifests.
- [ ] Group inference leaves ink, recognition segmentation and accepted transcriptions intact.
- [ ] Existing notebooks migrate with optional AST cache/boundary fields; old manual associations are refreshed automatically.

## AST and semantic analysis

- [ ] Future expansion: parse all supported numbers, symbols, arithmetic precedence, implicit multiplication, fractions, powers, roots, parentheses and relations into a portable stable AST/MathJSON. The current iPad path only accepts its documented bounded polynomial grammar.
- [ ] Infer candidate definitions and targets from equation ASTs and show the used sources for user verification.
- [ ] Persist exact-input AST caches for `t = 10`, `y = 2x + 11`, and target `t + 6y = 15`; invalidate caches when transcription changes and show detected definitions before calculation.
- [ ] Preserve unknown symbols; do not label prose or undeclared function calls as math without evidence.
- [ ] Reject unsupported syntax with a localized message and preserve source ink/transcription.
- [ ] Future expansion: round-trip supported AST to displayed math without changing grouping or relation semantics.

## Problem-local definitions and contextual solving

- [ ] Write nearby `t = 10`, `y = 2x + 11` and target `t + 6y = 15`; confirm the contextual action returns `x = -61/12` (manual device case still pending).
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


## Worksheet notation and contextual action

- [ ] Direct compute shows progress/cancel, immediate output, expanded card and visible failure; repeated saves reveal the answer.
- [ ] Numbered questions, separate columns and repeated function names isolate scopes; edits in another group do not invalidate this group.
- [ ] Function signatures and bound variables survive storage; derivative and integral requests resolve only same-scope accepted definitions.
- [ ] f-prime, double-prime, dy/dx and explicit first partial notation follow the supported workflows in `worksheet-math-workflows.md`.
- [ ] Bare differentials and unsupported differential equations never become accidental multiplication or ordinary equations.
- [ ] Source changes during asynchronous calculus execution reject save and preserve notebook ink.
