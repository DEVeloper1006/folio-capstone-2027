> Current UI: [row-first Calc 1 workflow](calc1-support.md). The following describes the earlier native polynomial milestone and retained legacy sheet; its polynomial-only restrictions do not describe the full current app.

# Offline polynomial integration

## Use

Write and recognize an expression, edit it if necessary, then **Accept & Save**.
Tap **Integrate** under that accepted row, confirm the variable, and choose
**Compute & Save**. The result appears immediately beneath the source in the
existing preview panel. It persists across app launches. Copy its LaTeX or use
**Remove result**. Unsaved editor changes disable Integrate until accepted.

Both forms are supported:

```latex
t^2+3t+2
\int (t^2+3t+2)\,dt
```

The result is:

```latex
\frac{t^{3}}{3} + \frac{3t^{2}}{2} + 2t + C
```

This is a deterministic native antiderivative, not an equation solver or worked
solution explanation. It does not change the source's mathematical verification
status. Recognition acceptance remains a separate user transcription decision.

## Supported mathematics

- One Latin-letter variable, inferred from the integrand or differential and
  confirmed in the sheet. Constant integrands default to x and allow another
  variable. Differentials must agree with variables in the integrand.
- Exact integer, decimal (up to nine fractional digits) and rational coefficients.
- Addition/subtraction, unary signs, multiplication (explicit or implicit),
  parentheses/braces, division by a nonzero constant, nonnegative integer powers.
- Braced `\frac`, `\dfrac`, `\tfrac`; `\cdot`, `\times`; standard spacing;
  `\left(`/`\right)` delimiter modifiers. Full indefinite integrals must end in
  `dx`, `dt`, another single-letter differential, or `\mathrm{d}x` equivalents.
- Input degree at most 20, output degree at most 21. At most 5,000 characters,
  512 AST nodes, 2,048 tokens and 64 nested groups/signs. Arithmetic uses checked
  Int64 rational values, reduces fractions, and reports overflow instead of
  approximating. Some intermediate expressions can exceed the exact-number
  budget even when a mathematically simplified answer would fit.
- An arbitrary constant is appended; integration in C uses C_{1} to avoid a
  name collision. The zero polynomial integrates to the constant alone.

Definite/nested integrals, additional variables/parameters, functions, equations,
matrices, Greek/multi-letter variable names and division by a variable produce
recoverable errors. Integral limits are never dropped. Zero to the zeroth power
is rejected. Bare letters are variables, not implicit named constants/functions.
This intentionally is not a general LaTeX parser or general-purpose CAS.

## Native architecture

`Services/PolynomialIntegrationService.swift` is Foundation-only, independent of
SwiftUI, SwiftData, recognition, networking and Python. Its tokenizer and recursive-descent parser build a private typed AST; that lowers to `PolynomialValue`, a
sparse degree → `ExactRational` map. Multiplication expands within the degree
budget. The service integrates coefficient-by-coefficient, then differentiates
the answer and requires exact equality with the parsed integrand before emitting
canonical LaTeX. `PreparedPolynomialIntegral` and `PolynomialIntegrationAnswer`
are immutable Sendable values; the answer exposes integrand/antiderivative
coefficients for reproducible checks. This is a bounded native IR, not a new
claim of general MathJSON support in Ink Pad.

`PolynomialComputationWorker` executes integration on an actor away from the UI.
The confirmation sheet parses the bounded accepted input, displays the integrand
and variable, awaits this worker, and saves on the UI actor. Cancellation is
checked before computation and before persistence. There is no server fallback.

`Services/PolynomialResultStore.swift` snapshots a current accepted source using
its stable step ID, latest accepted revision number, accepted fingerprint and
LaTeX. It validates current page-region membership and rechecks the snapshot
before saving. A changed source cannot receive a delayed result. Repeated runs
for the same accepted revision, variable and engine reuse the current record.

## Persistence and UI

`ComputationResult` is a separate SwiftData entity related to its source Step,
with operation, variable, revision number, fingerprint, input/output LaTeX,
engine version (`native-polynomial-v1`), creation time and stable ID. Step owns a
cascade relationship, so deleting a source removes its associated computations.
Existing models/schema registration are extended additively.

Current results appear under their source. Older revisions are retained under
**Previous results** and labeled **Outdated result**; they are not automatically
recomputed. Unaccepted editor changes also mark the visible result outdated so
it cannot be mistaken for an answer to the unsaved text. The card always shows
its input snapshot. Removal is persisted as a hidden-record flag: it disappears
from the UI, and recomputing creates a new result. The hidden record is retained
until its source is deleted. Save failures restore the local removal flag and
are displayed in the card.

Rendering uses the already bundled MathJax and structured JavaScript arguments.
No executable HTML is formed from input LaTeX. Original page strokes, model
output, accepted text and accepted revisions remain distinct from computed
results. The mock check/hint engine is not involved in this command.

## Verification

- The existing SymPy engine was used as an independent development oracle:
  **161 native cases matched**, including deterministic generated polynomials,
  products, exact decimals, variables and degree-20 input. **19 invalid cases
  were rejected**. No Python engine runs in the app.
- **40 simulator unit/integration tests passed**, including the 31 prior tests,
  parser precedence, variable confirmation, exact arithmetic, limits/overflow,
  duplicate prevention, stale/cancelled save rejection, source preservation,
  cascade deletion and disk-container reopen/removal.
- **Two UI tests passed** using a separate generated notebook: confirmation,
  computation, raw result, removal, unsaved-edit blocking, and recoverable
  unsupported-function input. Test scaffolding is DEBUG-only and does not seed
  the user's library.
- The physical M1 iPad generated-input test computed the expected antiderivative,
  rendered an SVG through the real WKWebView and saved a preview PNG. A second
  process reopened the result with its source, verified unchanged library counts,
  tested outdated-result handling/rejected stale saves and removal. It used a
  generated accepted transcription; it is not a handwriting accuracy benchmark.
- A separate DEBUG offline-check screen waits for `NWPathMonitor` to report no
  network route, then runs computation, persistence and local typesetting. Its
  report records whether that offline condition was observed. Physical network-
  disabled verification passed on the M1 iPad: the recorded run has
  `offlineVerified: true` and `physicalDevice: true`. The local SVG preview was
  generated successfully with no network route available.

Reproduce the CPU oracle (using existing local dependencies, no model downloads):

```sh
swiftc -O inkpad/inkpad/Services/PolynomialIntegrationService.swift scripts/PolynomialOracleCLI.swift -o /private/tmp/folio-polynomial-oracle
../folio-ipad-labs/experiments/folio-workspace/.venv-local-ocr/bin/python scripts/verify-polynomial-oracle.py --binary /private/tmp/folio-polynomial-oracle --engine ../folio-ipad-labs/experiments/folio-workspace/server/engine.py
```

Explicit DEBUG launch flags: `--polynomial-smoke`, `--polynomial-reopen`,
`--polynomial-offline-smoke`; isolated UI fixtures use `--polynomial-ui-test` and
optionally `--polynomial-ui-invalid`. Smoke stores/reports live under the app's
`Documents/PolynomialSmoke/`, separately from the user's notebook database.
Network monitoring exists only in DEBUG verification scaffolding. Core computation
has no networking API. The development profile-file write warning on smoke-test
exit is unrelated to computation and is retained in diagnostic logs.

## Checkpoint and rollback

Labs checkpoint: `.reports/polynomial-integration-20261105-010404/`. It retains
both repositories' pre-existing dirty source, original hashes/status/diffs, the
previous signed main app and the iPad's pre-change notebook database. The source
applier/rollback validate hashes and refuse to overwrite subsequent edits. Model
exports and the original recognition environments are unchanged.

Source rollback does not reverse a device schema migration. Older app reinstallation
may require the pre-migration database backup, which would replace newer device
edits. Device data restoration is therefore a separate explicit recovery action;
no automatic database overwrite or Git reset is performed.

## Remaining work

Handwritten slash commands, canvas placement, other calculus rules, equation
solving, RREF and worked explanations are outside this version. Recognition
accuracy and recognition latency remain independent concerns. Test real accepted
expressions manually; unsupported notation should stay editable and preserved.
