# Row-scoped computation workbench

The current workflow is documented in [Calc 1 coverage](calc1-support.md). This supersedes the older 14/29-operation polynomial-only workbench description.

## Interaction

- A row's rendered recognition preview has a checkmark to accept its transcription. Raw corrections are folded under Edit recognition.
- Choose an operation → Review inputs → Compute → Result → Insert result.
- Quick suggestions go directly to review with the operation visible. Choosing an operation never executes it.
- Review shows only required parameters. Full integral and limit notation supplies its own variable/limits/approach side. Optional edits and notation details are folded away.
- Compute persists the result; Insert remains an explicit separate action. No additional Save button is required in the visible flow.
- Results from another row never appear automatically. Each sheet has a fresh identity. RowComputationScope includes that source's history and only the current presentation's new results. A new free-form calculation has no inherited page-wide result context.
- Reuse is explicit and edited/reused inputs become independent typed computations. Accepted ink/transcription is preserved. A changed source cannot silently convert an unchanged old request into a detached result.

## Implementation

`ComputationWorkbenchView` owns choose/review/result stages. `ExpressionReviewRow` owns preview/checkmark/correction and creates fresh row computation presentations. `RowComputationScope` enforces result visibility. `MathResultStore` preserves source revision checks and deduplicates using the answer's actual engine version.

`MathComputationWorker` uses the exact native polynomial/matrix engine, with an isolated offline Calc1MathService path for supported elementary functions, limits and applications. Euler/scientific notation is routed to the elementary parser to avoid treating e as an ordinary polynomial variable. Request encoding masks unused fields so a hidden parameter cannot affect another operation. A cleared required limit is an error, not a silent default.

Native numeric matrices remain bounded at 6×6. Advanced calculations are bounded and do not constitute a universal CAS. See the coverage guide for the operation table, radians/log conventions, exact versus approximate outputs, interval-domain checks, time/evaluation limits and known gaps.

No persisted model schema, model weights or region-grouping changes were required. Existing histories remain in the notebook model. New free-form screens deliberately start a new session; reopening accepted handwriting rows gives access to their history.

## Verification

The native tests and reference oracle remain separate from Calc1MathTests and verify-calc1.py. The latter uses existing Node and SymPy installations and never downloads packages or opens user notebooks. Tests distinguish fixture-based UI interactions from real model inference. Device computation smoke uses an isolated store and checks persistence/main-library counts; see checkpoint logs for what actually ran.
