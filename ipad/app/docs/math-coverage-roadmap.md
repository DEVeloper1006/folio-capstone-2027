# Folio mathematics coverage and release roadmap

As of 2026-11-14. This is a computational coverage inventory, not a claim of curriculum certification, complete course coverage, handwriting accuracy, proof generation, or automatic word-problem interpretation.

## Evidence and status vocabulary

- **Implemented:** an app command reaches a local, bounded calculation path.
- **Tested examples:** named automated tests/oracles cover representative cases, not all inputs in that mathematical family.
- **Physical evidence:** earlier isolated iPad smoke exercised all 45 menu operations, rendering, insertion and reopen. The user also reported the previous Calc 1 workflow working. Those checks do not validate every topic, adversarial domain, or handwriting notation. New changes need their own device checks.
- **Partial:** supported subsets or significant missing semantics are stated explicitly.
- **Planned:** no integrated command is being claimed. A library containing a method is insufficient evidence.

The current source of truth is MathOperation/MathComputationService, AlgebraComputationService, PolynomialIntegrationService, PolynomialIntegralInput, Calc1MathService, Resources/calc1-worker.js and their tests. The previous signed build used native-math-v4; the previous release added native-math-v5 complex quadratic solving; native-math-v6 adds the bounded exact algebra batch described in exact-algebra.md. Extended calculus remains the pinned Nerdamer 2.0.1 adapter. Recognition and computation are separate pipelines.

## Curriculum sources and version boundaries

Research uses public official sources. Do not copy exam banks into the product; create original acceptance examples.

- [Ontario secondary course descriptions](https://www.dcp.edu.gov.on.ca/en/course-descriptions-and-prerequisites/mathematics), updated August 2026, explicitly retains the 2007 Grades 11–12 curriculum. Initial regional baseline: MCR3U/MCF3M functions, MHF4U advanced functions, MCV4U calculus/vectors, MDM4U data management. College/workplace courses add financial, measurement and practical applications; these are not automatically covered by university calculus commands.
- [Ontario Grades 11–12 mathematics curriculum](https://www.edu.gov.on.ca/eng/curriculum/secondary/math1112currb.pdf): detailed expectations, including sequences, functions, trigonometry, vectors, geometry, probability and statistics. Course description research is broad coverage evidence; individual expectation mapping must retain its own source section/page.
- [AP Precalculus course](https://apcentral.collegeboard.org/courses/ap-precalculus) and [topic overview](https://apcentral.collegeboard.org/media/pdf/ap-precalculus-course-at-a-glance.pdf): polynomial/rational, exponential/logarithmic, trigonometric/polar functions, with additional functions involving parameters/vectors/matrices. Course content and assessed content must be tracked separately.
- [AP Calculus AB/BC course topics](https://apcentral.collegeboard.org/media/pdf/ap-calculus-ab-bc-course-at-a-glance.pdf): limits/continuity, differentiation and its applications, integration and its applications, differential equations; BC additionally includes parametric/polar/vector-valued calculus and sequences/series. AB itself already includes separable differential equations; they are not exclusively Calc 2.
- [AP Statistics course](https://apcentral.collegeboard.org/courses/ap-statistics) and [current topic overview](https://apcentral.collegeboard.org/media/pdf/ap-statistics-course-at-a-glance.pdf): data collection/exploration, probability/distributions, inference for proportions and means, regression. The effective-fall-2026 course revision must not be confused with older unit numbering.
- [IB mathematics course overview](https://www.ibo.org/programmes/diploma-programme/curriculum/mathematics/), [current AA guide](https://www.ibo.org/globalassets/new-structure/university-admission/pdfs/dp-mathematics-analysis-and-approaches-guide-en.pdf), [current AI guide](https://www.ibo.org/globalassets/new-structure/university-admission/pdfs/dp-mathematics-applications-and-interpretation-guide-en.pdf): current first-assessment-2021 AA/AI SL/HL courses cover number/algebra, functions, geometry/trigonometry, statistics/probability and calculus. AA and AI have different emphasis and higher-level requirements; neither is interchangeable with AP Calculus.
- [IB announced AA changes](https://www.ibo.org/university-admission/latest-curriculum-updates/dp-mathematics-analysis-and-approaches-updates/) and [AI changes](https://www.ibo.org/university-admission/latest-curriculum-updates/dp-mathematics-applications-and-interpretation-updates/): track the announced 2029 assessment version separately. For example AA removes financial applications/bivariate data and HL Euler's method; AI removes selected topics including HL complex numbers/vector product/Poisson distribution. Retain useful existing tools rather than deleting them because a later syllabus changes.
- [OpenStax Calculus Volume 2 publisher preface](https://openstax.org/books/calculus-volume-2/pages/preface) gives a general Calc 2 reference scope: integration, differential equations, sequences/series, parametric/polar topics. College Calc 1/2 boundaries vary.

These public guides support the inventory; a line-by-line certification against every course expectation has not been completed.

## Current computational coverage

All examples below are original acceptance targets. “Existing tests” identifies representative source evidence; the release checkpoint records which suites were actually executed. No row below establishes corresponding handwriting recognition accuracy.

| Family | Current status / evidence | Example target | Important gaps or conditions |
|---|---|---|---|
| Arithmetic, fractions | Implemented; AlgebraComputationTests, polynomial tests | (3/4+2)/5 = 11/20 | Bounded exact Int64 rational operations; overflow returns an error |
| Polynomial simplify/expand, binary arithmetic/division | Implemented; AlgebraComputationTests | (x+1)(x−1) = x²−1 | Single variable; degree/expansion budgets; original denominator restrictions remain |
| Factoring | Partial; multiply-back verification in AlgebraComputationTests | x²−9 = (x−3)(x+3) | Rational linear-factor search; remaining factors are not necessarily irreducible |
| Linear/quadratic equations | Implemented real-coefficient equations, including new complex conjugate roots | x²+2x+5=0 → −1±2i | Degree ≤2; no general equation solver, complex coefficients, or arbitrary symbolic parameters |
| Complex arithmetic/polar form/De Moivre | Partial: exact rational complex arithmetic, conjugate and modulus added; polar/De Moivre planned | (1+i)(1−i)=2 | Quadratic output alone does not add complex input support |
| Inequalities / absolute-value equations | Partial: linear/quadratic polynomial inequalities and linear absolute-value equations added | x²−1≤0 → [−1,1] | Exact open/closed polynomial intervals implemented; rational/chained inequalities and general absolute equations remain unsupported |
| Rational/radical/exponential/log/trig equations | Partial numerical bracket only | cos(x)=x on [0,1] | One root, not all roots; extraneous roots and periodic families need explicit verification |
| Systems | Exact numeric augmented linear systems implemented | x+y=3, x−y=1 → (2,1) | Matrix entry; no handwritten multi-equation system extraction or general nonlinear solver |
| Composition/inverses/transforms | Partial: polynomial A(B(x)) added; inverses/transforms planned | f=x², g=x+1 → f(g(x))=(x+1)² | General inverse needs branch/domain choices |
| Trigonometric function evaluation | Implemented elementary path; Calc1MathTests | sin(π/6)=1/2 | Radians only; degrees require explicit future request/UI settings |
| Triangle/coordinate geometry | Planned | right triangle 3,4 → hypotenuse 5 | No diagram interpretation; ambiguous SSA cases must expose alternatives |
| Limits | Partial symbolic finite/infinite/one-sided; Calc1MathTests | lim sin(x)/x at 0 =1 | Unresolved is not proof of DNE; general piecewise/oscillatory cases incomplete |
| Continuity/domain/asymptotes | Partial conservative domain checking | 1/x excludes zero | No complete function-analysis command, graph or removable-hole classification |
| First/second derivatives | Implemented elementary families; Calc1MathTests/oracle | d(sin x)/dx=cos x | Real domain; abs/fractional powers qualified away from zeros |
| Tangent/normal, average rate | Implemented; Calc1MathTests | x² at 2 → tangent y=4x−4 | Finite supported derivative; cusps/vertical tangents need additional analysis |
| Implicit differentiation | Partial x,y local derivative | x²+y²=1 → −x/y where y≠0 | No general multivariate bindings or related-rates input |
| Higher derivatives/linearization | Second derivative exists; dedicated arbitrary-order/linearization planned | linearize sqrt(x) at 4 | Must bound order and preserve point-domain constraints |
| Critical points/extrema/concavity/optimization | Planned dedicated analysis | x² on [−1,2] → min0/max4 | Must include endpoints, derivative undefined points, original-domain boundaries; sampled roots are not exhaustive |
| Motion/related rates | Partial underlying derivative/integral tools | velocity=position derivative | No automatic text formulation, units engine, total-distance split workflow or related-rates command |
| Indefinite integration | Partial checked symbolic + exact polynomials | ∫x eˣ dx=eˣ(x−1)+C | Not every integral has an elementary primitive; differentiating a candidate must validate it |
| Finite definite integration / average value | Implemented on supported continuous intervals; DefiniteIntegralTests, Calc1MathTests | ∫₀^π sin(t)dt=2 | Original input domain matters; conservative rejection can reject valid removable/split cases |
| Explicit numerical integration | Implemented adaptive Simpson; Calc1MathTests | ∫₀¹e^(−x²)dx≈0.746824 | Error estimate is not a certified error bound; finite continuous intervals and evaluation budgets |
| Riemann/trapezoid/Simpson classroom sums | Planned dedicated commands | left/right/midpoint sums with n subintervals | Need n, convention, sampled table support and clear approximate labels |
| Area/volumes/arc length | Partial existing operations; Calc1MathTests | area x vs x² on [0,1] =1/6 | Numerical area/length; fixed axes/radius restrictions; shifted axes, cross sections and y-based regions missing |
| Improper integration | Planned | ∫₁^∞x⁻²dx=1; ∫₁^∞x⁻¹dx diverges | Independent one-sided limits at every singularity; principal value must never substitute for ordinary convergence |
| Differential equations | Planned | y′=y, y(0)=1 → eˣ | Start separable/first-order and verify equation+initial condition; retain equilibrium solutions and domain intervals |
| Euler/numerical ODEs | Planned | y′=y, step0.1 | Step size, direction, initial point, error interpretation and budgets |
| Parametric/polar calculus | Planned | x=t²,y=t³ → dy/dx=3t/2 for t≠0 | Coordinate-specific schemas and parameter intervals; singularities and multiple tracing matter |
| Sequences/finite sums | Planned | geometric sum 1+2+4+8=15 | Discrete index scope, integer bounds and recurrence semantics |
| Infinite series/convergence | Planned | Σ1/n² converges; Σ1/n diverges | Test hypotheses and endpoint checks; numeric partial sums do not prove convergence |
| Taylor/Maclaurin/power series | Planned | exp(x) through degree3 | Center/order/radius/interval and remainder qualifications; polynomial alone is not convergence proof |
| Matrices | Implemented bounded exact numeric operations; MathComputationTests, AlgebraComputationTests/native oracle | RREF [[1,2],[3,4]]=I | Up to6×6; no symbolic matrices/eigenanalysis command |
| Vectors/lines/planes | Planned dedicated commands | (1,0,0)×(0,1,0)=(0,0,1) | Matrix arithmetic is not a vector-geometry workflow; distinguish points, directions and dimensions |
| Combinatorics/probability | Planned | choose(5,2)=10 | Count bounds, event assumptions, independence vs mutual exclusivity |
| Descriptive statistics/regression | Planned | mean(1,2,3)=2 | Dataset input, sample vs population variance, missing data, regression diagnostics |
| Distributions/inference | Planned | normal CDF, binomial tail, confidence interval | Tail conventions, inverse probabilities, significance/confidence, validity conditions and stable numeric implementations |
| Financial mathematics | Planned | compound growth/annuity | Period/rate alignment, payment timing, units and rounding conventions |
| Graphs/tables | Planned | graph x²−1 and its roots | Sampling must not imply continuity, root completeness, or exact domain knowledge |
| Proofs/theorems/word-problem reasoning | Not implemented; separate product scope | IVT/MVT justification | Computation alone does not establish hypotheses, proof, units or model validity |

## Ordered release batches

### 1. Inline review + quadratic completeness (this release)

Deliver complex quadratic roots, prominent existing method/condition text, compact previews beneath pending rows and explicit inline acceptance. Crowded rows use a Preview tab and expandable overlay; do not move the original ink. Accept is transcription confirmation, not correctness verification. Review math retains the correction sheet. Rendering/acceptance must reject stale identities. No model or grouping changes.

### 2. Algebra and functions

Start with exact polynomial/rational inequalities, linear systems entry, absolute-value equations, complex arithmetic, composition and restricted inverse functions. Add explicit angle mode for new trig workflows. Prioritize original-domain tracking and substituting candidate roots back into the original equation. Then add carefully bounded higher-degree/root and exponential/log/trig families; distinguish exact solution sets, approximate roots and unresolved cases. Graph/table presentation is useful but cannot certify missing roots. Each command needs its own minimal review form rather than reusing unrelated calculus fields.

### 3. Remaining Calc 1 gaps

Structured piecewise/domain handling precedes general continuity, nonsmooth derivative and extrema analysis. Add higher derivatives, linearization, critical points and endpoint-aware extrema, classroom quadrature, accumulation functions and motion workflows. Preserve existing domains before simplification. Related-rates/optimization start from user-formulated mathematical models, not inferred word problems. Add variable-axis/cross-section integration applications after explicit coordinate/axis review.

### 4. Selected Calc 2 / AP BC

Add improper integrals only with per-singularity convergence checks, then first-order separable ODEs/initial conditions and Euler's method. Add parametric/polar operations with distinct coordinate/parameter bindings. Introduce discrete indices before finite sums, elementary sequence/series families and Taylor polynomials. General series convergence is not a universal CAS toggle. Unsupported or inconclusive tests must remain inconclusive. Multivariable and double/triple integrals follow these foundations in a later release.

### 5. Geometry/vectors, probability/statistics

Use separate typed input/review components for vectors, lines/planes, triangles and datasets. Add stable numeric distribution primitives and independent reference values before inference tools. Explicitly request sample/population conventions, degrees/radians, confidence/tail/alternative and required assumptions. Use standard formula names with stated conditions; do not describe every numerical result as an explanation or proof. Finance can reuse scalar arithmetic after adding rate/period semantics.

## Acceptance corpus and release gates

For each new command store original examples, expected semantics, domain, independent oracle/reference, exact-vs-approximate status and tolerances. Include nominal, boundary, malformed, unsupported, overflow/time-budget and branch/domain cases. Test both plain and supported LaTeX forms where applicable. A notation accepted by a computation parser is not evidence that TexTeller recognizes it.

Keep separate scorecards for: (1) typed computation correctness, (2) rendered outputs, (3) saved/reopened provenance and insertion, (4) real Pencil recognition/grouping/correction and (5) physical-device interaction. Recognition metrics should include exact normalized transcription, mathematical equivalence only where safely decidable, grouping errors, correction frequency and latency. Do not pool fixture-recognizer UI results with real handwriting.

Current unit/integration references: AlgebraComputationTests, MathComputationTests, PolynomialIntegrationTests, DefiniteIntegralTests, Calc1MathTests, ExpressionReviewTests and ExpressionWorkflowTests. UI references: AlgebraUITests, ComputationUITests, DefiniteIntegralUITests, Calc1UITests, ExpressionWorkflowUITests, CanvasUITests. scripts/verify-native-math.py and scripts/verify-calc1.py are existing independent SymPy comparisons; this release adds a complex-quadratic oracle. Test counts belong in the release checkpoint, not inferred from the existence of these files.

Before installation: guarded source checkpoint, signed previous app, notebook database backup, focused regressions and independent comparisons. After installation: real Pencil pen/eraser/lasso/undo, inline accept/edit, crowded rows, result insertion/movement, offline computation and reopen. Keep recognition-model weights and grouping unchanged in batch1.

## Deferred correction editor (explicit product requirement)

Replace raw LaTeX editing with a visual mathematical editor: fractions, superscripts/subscripts, radicals, integral bounds/differentials, functions, piecewise forms and matrix cells. Keep LaTeX as an advanced/export option. Preserve an internal structured representation and distinguish ambiguous parses rather than guessing. A future natural-language entry layer is separate from the visual editor and must show the interpreted math for confirmation. This editor is recorded for later, not implemented in this release.

## Exact algebra batch update

See [exact-algebra.md](exact-algebra.md): six commands delivered from batch2 (polynomial inequality, linear absolute-value equation, polynomial composition, complex calculation/conjugate/modulus). This is a tested subset of the broader batch, not completion of every listed topic. Side previews now live under the row-control button, with explicit expansion and scrolling.
