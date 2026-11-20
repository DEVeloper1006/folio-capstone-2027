# Calc 1 coverage and the row-first workflow

This is a broader offline calculation foundation, not a claim that every Calc 1 problem or arbitrary integral is solved. Runtime verification is recorded in the checkpoint logs. Recognition accuracy was not expanded by changing the calculation engine.

## Student workflow

1. Write and pause. Each pending row shows a compact rendered preview in the side control rail, below Review math and above Accept. Expand opens a larger scrollable preview.
2. Check the rendered recognition preview. Tap **Accept** directly on the notebook page to confirm it. **Review math** opens correction; raw LaTeX and alternatives are under **Edit recognition**. The original ink stays intact; there is no separate Save step in the visible flow.
3. Tap the suggested calculation or **Choose an operation**.
4. The operation menu leads to **Review inputs**. That screen shows the row, recognized variable/limits, and only the parameters the operation needs. Editing, notation details and the variable override for constant expressions are folded away.
5. Tap **Compute**, review its result, then **Insert result**. Compute persists the calculation; insertion remains a separate, explicit action. Results remain movable with finger or Pencil.

On narrower iPad layouts, secondary notebook actions (recognition settings, export, command palette and mode) are in the More menu so the drawing tools and Compute do not overlap. Full-width landscape keeps the existing direct actions. Narrow Split View layouts remain a separate verification target.

Each row presentation has a fresh identity. History and reuse are scoped to the initiating row plus results created in that presentation. Another row's results never appear automatically. A new free-form toolbar calculation starts a fresh session. Existing saved objects remain in the notebook model; the new free-form screen does not automatically load page-wide history. Accepted handwriting histories are accessible by reopening their row.

**Use this result as input** is explicit. Edited/reused inputs are independent typed computations with their request preserved; the accepted transcription is not overwritten. Current exact-real solved scalars can be reused by later same-group calculations with stored result-level dependencies; arbitrary result/function chains remain bounded. See `integration-mini-demo.md`.

## Input conventions

- One real independent variable, normally x or t. Euler's e and π are constants; i is reserved for complex numbers and is not an independent variable in this adapter.
- Plain input or supported LaTeX: `sin(x)` / `\sin x`, fractions, parentheses, powers, roots and implicit multiplication. `sin^{-1}(x)` means inverse sine; use `1/sin(x)` or csc for its reciprocal.
- Angles are radians. `ln` is natural log; `log` is base 10. `log_{b}(x)` supplies another constant base.
- Scientific notation such as `1e-3` is recognized. Huge expressions, expansions and powers are bounded.
- Full integrals carry their differential and limits: `\int_0^{\pi} \sin t\,dt` supplies t, 0 and π. Full limit notation can supply the point and side: `\lim_{x\to0^{+}} \ln x`.
- Explicit function definitions such as `y=sin(x)` or `f(t)=sin(t)` are supported for function/calculus operations. General equation solving remains a different operation. A bracketed numerical root can also accept `cos(x)=x`.
- Matrices use the existing numeric grid/LaTeX input. General symbolic matrices are not added.

## Available calculations

| Area | Implemented path | Examples / boundaries |
|---|---|---|
| Arithmetic, polynomial algebra | Existing exact native engine, with elementary constant/simplify/expand fallback | Fractions; expand/combine terms; verified rational polynomial factors; real-coefficient linear/quadratic equations with complex roots; polynomial arithmetic/division/equivalence. General symbolic equation solving is not claimed. |
| Differentiation | Symbolic first/second derivatives | Powers, product/quotient/chain rule, rational, exponential/log, six trig functions, inverse trig, and common hyperbolic functions. For example d(sin x)/dx = cos x. |
| Indefinite integration | Exact native polynomial path or checked symbolic antiderivative | Powers, trig, rational/logarithmic forms, supported substitutions/by-parts patterns, e.g. ∫x eˣ dx = eˣ(x−1)+C. Candidate is accepted only when the backend simplifies F′−f to zero. Natural logs are rendered with absolute values for real antiderivatives. |
| Definite integration | Native exact polynomials or symbolic FTC on a conservatively continuity-checked finite interval | ∫₀^π sin x dx = 2. Limits can contain finite constants such as π, e and numeric expressions in the elementary path. Reversed limits are valid for a signed integral. |
| Numerical definite integration | Explicit separate operation, adaptive Simpson | ∫₀¹e^(−x²) dx ≈ 0.74682413281. Approximate output contains ≈ and an estimated error/evaluation count. No silent replacement of an unsupported symbolic integral. |
| Limits | Symbolic two-sided, left, right and infinite-point limits | sin x/x → 1 at 0; 1/x → −∞ from the left and +∞ from the right; (1+1/x)^x → e at +∞. Unresolved output is an error, not proof of existence or nonexistence. |
| Evaluate | Finite real substitution | Evaluate a function at a constant point; symbolic constants may remain exact. |
| Tangent and normal lines | Function value and finite derivative at a reviewed point | f=x², a=2 → tangent y=4x−4; a horizontal tangent gives a vertical normal. Cusp, singular or unsupported derivative forms can be rejected. |
| Implicit differentiation | Local dy/dx for an equation in x and y | x²+y²=1 → dy/dx=−x/y where F_y≠0. This is not an ODE solver or general multivariable calculator. |
| Average rate / value | Secant slope / integral divided by interval length | Distinct endpoints required for averages. |
| Area between curves | Numerical ∫abs(f−g) | Accounts for curve crossings; nonnegative result on lower≤upper. Both curves must use the same variable. |
| Volumes | Disks / washers about x-axis; shells about y-axis | Disks π∫f²; washers π∫(R²−r²), with certified nonnegative radii R≥r; shells 2π∫x abs(f), x≥0. Axis is explicit; shifted axes/regions must be reformulated. Shell sign changes use a marked numerical result. |
| Arc length | Numerical ∫sqrt(1+f′²) | Finite interval and supported differentiable function. |
| Numerical root | Bisection in a continuity-checked bracket | cos x=x on [0,1] → x≈0.73908513321. Finds one bracketed root, not all roots. No sign change is not proof of no roots. |
| Numeric linear algebra | Existing exact native engine | RREF/rank/determinant/inverse/transpose, add/subtract/multiply, augmented systems, trace/scaling/integer powers and null/row/column-space bases; dimensions stay bounded. |

## Important limits on coverage

- No universal CAS claim. Not all elementary-looking integrals have elementary antiderivatives. An unresolved candidate is rejected rather than presented as solved; use the explicit numerical option where appropriate.
- Improper integrals (infinite limits, poles, or endpoint singularities) are not automatically classified for convergence. The interval-domain checker deliberately rejects uncertain cases, including some removable singularities or cases that could be handled by splitting/substitution.
- Interval checks are conservative and can reject valid expressions due to dependence/branch uncertainty. They do not constitute a formal theorem prover. Numerical quadrature error is an estimate; difficult oscillatory or sharply concentrated functions need additional care and may exceed budgets.
- Absolute-value/fractional-power derivative formulas carry explicit qualifications away from zero arguments. Additional zero points need separate one-sided analysis. This does not declare all such zero points nondifferentiable. Cusp/vertical-tangent analysis and general piecewise functions are not complete.
- Symbolic limits are those resolved by the pinned backend and tested adapter. Unsupported and nonexistent cases can both return a recoverable error; the app does not label every unresolved limit DNE.
- Domain exclusions from the original input remain in force after simplification. Input ASTs, rather than simplified CAS expressions alone, are used for interval checks.
- Implicit derivatives use x,y; evaluation requiring two independent substitutions and general related-rates/optimization word-problem interpretation are not implemented. Students can use derivative/root/evaluate tools on a formulated problem, but the app does not infer the formulation or enumerate all extrema.
- No full complex algebra, arbitrary-parameter algebra, general transcendental equation solver, Riemann-sum/series calculator, theorem proofs or explanation generator.
- Recognition grouping, the TexTeller model and its weights are unchanged. Correctable transcription is the bridge; this work does not establish Calc 1 handwriting recognition accuracy.

## Architecture and execution limits

`MathComputationWorker` preserves the exact native matrix/polynomial implementation. Supported non-polynomial operations use `Calc1MathService`, which creates a fresh local Web Worker in an ephemeral WKWebView. A strict bounded mathematical tokenizer/AST admits a defined function/operation vocabulary; user strings are never executed as JavaScript. No symbol assignments or backend session state cross rows.

The bundled symbolic engine is **Nerdamer 2.0.1**. The published package SHA-512 was checked before extracting the 630,546-byte bundle; its SHA-256 and source URL are in Resources/nerdamer-manifest.json. Apache-2.0 and bundled decimal.js notices are retained. No npm installation scripts run. The library is loaded from the app bundle, with `connect-src 'none'` and blob workers; no Mac worker or network download is involved in calculation.

Each worker has an 8-second deadline and can be terminated. A 12-second native watchdog covers page loading as well. Cancellation disposes the request. Parsing is limited to 2,000 source characters, 400 tokens, 160 AST nodes and 32 nested groups. Powers have magnitude at most 1,000; expansions estimated above 500 terms are rejected. Numerical quadrature is limited to 30,000 evaluations / 18 adaptive levels with a stated tolerance. Budget exhaustion returns an error and saves no fabricated answer.

Native results use `native-math-v6`; extended results record `native-math-calc1-v2-nerdamer-2.0.1`. Deduplication uses the answer's actual engine version. Existing history remains visible; no persisted model schema changes are required.

Primary references: [Nerdamer API](https://nerdamer.com/docs/api/nerdamer/), [calculus API](https://nerdamer.com/docs/api/calculus/), [limit behavior](https://nerdamer.com/docs/api/calculus/limit-dir/), [pinned package](https://registry.npmjs.org/nerdamer/2.0.1), [Worker termination](https://developer.mozilla.org/en-US/docs/Web/API/Worker/terminate).

## Validation and deferred milestones

The checkpoint includes exact simulator/device logs. `Calc1MathTests` covers symbolic/numerical examples, function definitions, variable/limit extraction, cancellation of a genuinely busy worker, deadlines, source provenance/deduplication/reopen, and row isolation. `Calc1UITests` verifies preview→operation→review→result and that another row cannot inherit a result. Existing canvas/algebra/integral tests remain regressions.

`verify-calc1.py` uses an already-installed SymPy as an independent oracle, translating whitelisted result ASTs without eval. It includes symbolic comparisons, branch samples and numeric tolerances; its pass count is not a universal correctness proof. The existing native oracle remains separate. The real-device computation smoke exercises all menu operations in an isolated store; a fixture-driven test is not handwriting accuracy evidence.

Next steps after this build is stable:

1. Build a student-example acceptance corpus across these Calc 1 topics; measure both recognition and computation, including domain failures and correction usability.
2. Strengthen improper-integral, nonsmooth/critical-point and domain analysis before advertising complete Calc 1 coverage; add explicit numeric-method/Riemann-sum and graph-assisted workflows where useful.
3. Introduce structured multi-variable bindings and nested bound scopes before double/triple integrals. Keep these as distinct command schemas instead of adding unrelated fields to the single-variable screen.
4. Add polar/parametric coordinate-aware operations, then sequences/series with separate discrete indices and convergence semantics.
5. Treat differential equations as equation/initial-condition problems with their own validation and solution checking. Backend code existing in a library is not evidence that these app features are integrated or tested.

## Broader coverage roadmap

See [math-coverage-roadmap.md](math-coverage-roadmap.md) for source-linked Ontario/AP/IB topic coverage, unsupported areas and staged releases, including the deferred visual math editor. Complex roots apply to real-coefficient linear/quadratic equation solving; this does not enable general complex input or complex calculus.

The next exact algebra batch adds polynomial inequalities, linear absolute-value equations, polynomial composition and rational complex calculations. See [exact-algebra.md](exact-algebra.md) for syntax and boundaries; the menu now has51 operations.

For current trig-substitution families, rational fallback, finite Split definite integral, and demo readiness, see [integration mini demo](integration-mini-demo.md). Improper integrals and arbitrary piecewise functions remain outside the split command.
