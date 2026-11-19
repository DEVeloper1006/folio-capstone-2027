# Folio mini demo and integration acceptance guide

Use the checkpoint recorded in `problem-context-checkpoints.md`. The local TexTeller encoder, decoder, tokenizer and manifest must be present. The mathematical demo assumes that each transcription is reviewed and corrected before acceptance; this is not a claim of flawless live handwriting recognition.

## Recommended five-minute demo

On a fresh page, write these nearby rows in this order, with one expression per row:

1. `t = 10`
2. `f(x) = 3x^2`
3. `t + 6a = 22`
4. `\int_0^a f(x) dx`

Accept each transcription. Open row 3 and verify its source summary, then **Verify & Solve**. It should show `a = 2`. Open row 4 and check that its source summary names both `f(x)=3x^2` and the **solved result** `a=2`. Tap **Verify & Compute**. Expected final answer: **8**.

The result explanation should expose the actual sequence: expand f; find `F(x)=x^3`; substitute the solved upper bound 2; calculate `F(2)-F(0)=8-0`. This demonstrates substitution → solve → integrate → substitute/evaluate. No copying a solved answer into a new setup field is required.

Why a definite integral: an indefinite integral is `x^3+C`; evaluating it at 2 gives `8+C`, not 8, unless an initial condition fixes C. In a definite integral the constant cancels. Do not silently remove C for a numeric demo.

For reliable presentation, recognize/review the page beforehand and demonstrate calculation live. Keep a second, fully checked page as a fallback. Show one extra integration example below, then the domain-rejection example. Avoid unreviewed dense pages or unsupported symbolic-bound/differential-equation questions in a mini demo.

## What to test individually

Use a fresh page or clearly separated exercise for each example. For an integral row, use its suggested operation, or **Choose an operation → Calc 1 → Antiderivative / Definite integral → Review inputs → Compute**. For the split examples choose **Split definite integral**. Check the variable and any bounds before running.

| Part | Input/action | Expected check |
| --- | --- | --- |
| Algebraic substitution and solve | Main demo rows 1–3 | `a=2`; sources show t, with no values from another exercise. |
| Solved value reused in integration | Main demo row 4 | Exact answer 8; source summary includes the saved solved result; method shows `F(x)=x^3` and endpoint values. |
| u-substitution type | `\int 2x/(x^2+1) dx` | `ln(x^2+1)+C`; valid for real x. Accepted by symbolic differentiation, not merely a plausible-looking expression. |
| u-substitution with trig | `\int 2x cos(x^2) dx` | `sin(x^2)+C`. This calculates a substitution-type integral; it is not a full tutor for handwritten u/du transformations. |
| Trig substitution | `\int sqrt(9-x^2) dx` | `(x sqrt(9-x^2)+9 asin(x/3))/2+C`; substitution and domain are shown. Antiderivative on `-3<x<3`; integrand is real on `[-3,3]`. |
| Trig definite integral | `\int_0^3 sqrt(9-x^2) dx` | `9 pi/4`. |
| Other radical families | `\int sqrt(9+x^2) dx`, `\int 1/sqrt(x^2-9) dx` | First has a real logarithmic form for all real x; second gives `ln|x+sqrt(x^2-9)|+C` on each of `x<-3` or `x>3`. No claim that every algebraic radical matches these bounded templates. |
| Rational / partial fractions | `\int 1/(x^2-1) dx` | `(ln|x-1|-ln|x+1|)/2+C`; x≠±1. Each connected domain component can have its own integration constant. |
| Rational with nontrivial numerator | `\int 3x/(x^2-x-2) dx` | `ln|x+1|+2ln|x-2|+C`; x≠−1,2. |
| Split at an absolute-value corner | `\int_{-1}^{2} |x| dx`, choose Split definite integral and leave split points blank | Auto-detects the affine absolute-value corner 0. Reports segments `[-1,0]≈0.5`, `[0,2]≈2`, total `≈2.5` with an error estimate. It is explicitly numerical. |
| Explicit split points | Same input, split point `0` | Same segmented result. Duplicate or out-of-range split points must produce a clear error. |
| Unsafe domain / pole | `\int_{-1}^{1} 1/x dx`, including Split definite integral with split point `0` | Rejects the pole/improper endpoint. **It must never return 0 by cancelling two divergent sides.** |
| Log/root domain | Definite `ln(x)` on `[-1,1]`, or `sqrt(9-x^2)` on `[0,4]` | Rejects the invalid real domain. |
| Prefix stability | Solve row 3 before accepting row 4 | Accepting later working must not make the earlier solve stale. |
| Dependency invalidation | After getting 8, remove the saved `a=2` result or change t | The integral answer becomes outdated; it cannot still claim to use that solved result. Recompute sources in order. |
| Two independent problems | Put another exercise on a different page, below a clear boundary or in a separate detected group | No cross-group solved value/function reuse. Nearby unnumbered work still needs source-summary verification. |

## Current implementation boundaries

- Standard one-variable substitution patterns use the existing symbolic engine, with verification. The app does not interpret arbitrary handwritten equations like `du=2x dx` as a complete change-of-variable proof.
- The three canonical quadratic-radical families use recognized, domain-qualified trig-substitution formulas with an algebraic/chain-rule certificate. Translated/scaled/general radicals outside those patterns may still be rejected. The app never upgrades a numeric sample check into a symbolic proof.
- Rational integration can fall back to real partial-fraction decomposition and verify the result by differentiating. It is not a complete arbitrary rational-function teaching system.
- Split definite integration handles finite continuous segments, automatically finding affine absolute-value corners or using up to eight user-provided interior split points. It does not infer a complete general piecewise function, solve arbitrary domain boundaries, or classify improper convergence.
- A single current exact real solution from an earlier same-group equation may become a scalar binding. Multiple/complex/approximate solutions are not silently chosen. Reused solved results retain result-level provenance; deleting/changing them invalidates dependents. Chains are bounded to prevent cycles/deep recursion.
- Stored context now uses the problem prefix through each target. Later rows do not invalidate earlier results, while changes to the prefix still do. Older results stored with a full-group manifest may need recomputation once.

## Sources

- [OpenStax: Trigonometric substitution](https://openstax.org/books/calculus-volume-2/pages/3-3-trigonometric-substitution): branch/domain restrictions and substitution families.
- [OpenStax: Partial fractions](https://openstax.org/books/calculus-volume-2/pages/3-4-partial-fractions): decomposition and real logarithmic antiderivatives.
- [OpenStax: Improper integrals](https://openstax.org/books/calculus-volume-2/pages/3-7-improper-integrals): each singular side needs its own limit; ordinary segment addition cannot replace convergence analysis.

## Readiness and evidence

**Ready for a prepared mini demo of the four-row workflow.** The full interaction was rehearsed in the simulator: solved a=2, accepted the later integral without invalidating the solve, observed the exact answer 8 with antiderivative/endpoint details, then removed the solved source and confirmed the integral became Outdated with insertion disabled.

Both iOS simulator and device builds passed. Existing checks passed 104 unit cases, six compute/integral UI cases and 96 independent calculus cases; the checkpoint record includes exact logs and final-source reruns. Radical-formula derivatives were also checked independently with SymPy. Trig/rational/split examples were executed directly in the engine; they have not each received a dedicated UI rehearsal. The new result-dependency and splitting paths have no newly added automated tests because the repository pauses test development.

Live physical-iPad handwriting accuracy, a complete two-column exercise sheet and arbitrary substitution/domain cases remain acceptance work. For the demo, prepare/review the page first, compute live, and have a checked backup page. This is a bounded math notebook demonstration, not universal CAS or complete worked-solution tutoring coverage.
