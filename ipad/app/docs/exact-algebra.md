# Exact algebra batch and side recognition rail

2026-11-14. Native engine `native-math-v6`; six added operations bring the menu to 51 commands. This extends the previous real-coefficient quadratic solver (which already returns complex roots). It is not a universal equation solver or a complete precalculus course implementation.

## Side preview flow

Pending rows display a card in the trailing control rail, aligned with the row. The card has **Review math** at the top, a rendered mini preview below, then **Accept**. An expand icon opens a larger view; the full expression can scroll horizontally and vertically at readable size. Shrink returns to the mini preview. The side rail itself scrolls when visible rows require more room.

Accepted rows collapse to Compute. Review math retains the current correction sheet, candidates and Clear transcription action. Acceptance still confirms transcription only, and checks the displayed row ID, fingerprint, text and current drawing before persisting. No ink or result coordinates move. Only actual displayed card rectangles intercept touches, including after scrolling the rail; blank canvas passes through to PencilKit.

Recognition images use serialized rendering and a bounded decoded-image cache. The recognition renderer preserves the full logical expression size for expanded scrolling, with caps of width<6000 points, height<1400 points and area<400,000 square points, rasterized at2px/point. Exceeding a cap produces a recoverable preview failure with Review math available. Result insertion retains its previous, separate3px/point bounds and sizing. Malformed typesetting does not enable inline acceptance.

## Added operations

| Operation | Enter | Expected output / interpretation |
|---|---|---|
| Solve polynomial inequality | `x^2-1<=0` | x∈[−1,1] |
| Solve polynomial inequality | `x^2-1>0` | x∈(−∞,−1)∪(1,∞) |
| Solve absolute-value equation | `\|2x-3\|=5` (type vertical bars without escaping), or `abs(2x-3)=5` | x∈{4,−1} |
| Compose A(B(x)) | A=`x^2+1`, B=`x+2` | x²+4x+5; the outer expression is applied to the entire inner expression |
| Calculate complex expression | `(1+i)/(1-i)` | i |
| Complex conjugate | `3+4i` | 3−4i |
| Complex modulus | `3+4i` | 5; `1+i` yields √2 |

Use notebook→Compute→Algebra, choose the operation, review its inputs, then Compute. Recognition suggestions route polynomial inequality notation, absolute-value equations and supported complex expressions to the relevant command. A suggestion does not execute it. Composition requires an explicit second expression.

### Inequalities

- Exactly one relation: `<`, `>`, `<=`, `>=`, ≤, ≥, or supported `\le`/`\leq`/`\ge`/`\geq` LaTeX.
- One real variable, inferred from the expressions, with rational/decimal coefficients. Scientific notation is explicitly rejected in this batch rather than treating E as a variable. After moving both sides left, degree must be at most2.
- Exact discriminants and algebraic endpoints determine intervals. No numerical sampling establishes a sign chart. Strict comparisons exclude zeros; non-strict comparisons include them.
- Linear, constant, negative-leading-coefficient, repeated-root, no-real-root and identity/contradiction cases are handled explicitly.
- No chained relations, variable denominators, general piecewise, higher-degree or transcendental inequalities. Rejection does not mean there are no solutions.

### Absolute-value equations

- Supported form is `|a*x+b|=c` or `abs(a*x+b)=c`, with a constant right side. `\left|...\right|` and `\lvert...\rvert` are accepted wrappers.
- For c≥0, solve both signed linear equations, deduplicate and verify each root in the original absolute-value equation. A negative right side has no real solutions.
- Constant identities/contradictions are supported. Higher-degree interiors, additional terms outside the bars, nested bars, and variable right sides are not yet supported.

### Composition

- A and B are polynomial bodies in the same single variable; do not enter `f(x)=...` headers here.
- Compute A(B(x)), not B(A(x)). Result degree is bounded at20; coefficient overflow is an explicit error.
- Constants and a zero inner expression are supported: `(x^3+2x+3)` composed with0 is3. A constant term is substituted directly, without evaluating0^0.
- This does not add inverse functions, branch selection, general rational/function composition or multi-variable substitutions.

### Complex numbers

- Exact Gaussian rationals a+bi, using rational arithmetic, i²=−1, parentheses, implicit multiplication, simple LaTeX fractions and nonnegative integer powers0–20.
- Division multiplies by the denominator's conjugate and rejects a zero denominator. 0^0, unsupported powers, arbitrary variables/functions and complex radicals are rejected.
- Modulus is nonnegative √(a²+b²), simplified when it is a rational square. This is not complex-valued calculus, general complex-coefficient equation solving, polar form or De Moivre support.
- Valid rational complex expressions can be explicitly reused in a new complex calculation. Solution sets/intervals are not offered as scalar expression inputs; irrational modulus outputs are not reused through an incompatible parser.

## Implementation and validation

`MathOperation` supplies native algebra classification, field requirements and menu labels. `AlgebraComputationService` supplies bounded solving/composition; `ExactComplexValue` in PolynomialIntegrationService reuses the existing mathematical AST. `Calc1MathService.supports` explicitly excludes these commands so unsupported inputs cannot silently change solver/domain via fallback. The workbench uses a native preflight for this batch; unrelated point/bounds/B values are masked by request encoding. Original accepted ink, row result provenance and explicit insertion remain unchanged. No persisted model fields were added; existing v5 results retain their original engine version.

`AlgebraComputationTests` covers nominal, boundary, malformed and overflow cases. `ExpressionWorkflowTests` covers side placement and stale acceptance. UI tests cover direct acceptance, correction, expansion, wide-expression scrolling, shrink, drawing outside the rail and the six operation flows. `verify-algebra.py` independently compares640 cases with an existing SymPy installation:320 inequality solution sets,70 absolute-value equations,210 complex operations and40 compositions. The benchmark uses exact comparisons and a whitelist LaTeX parser; it is not a handwriting-accuracy benchmark or proof for every possible input. Release-specific executed test and device evidence is in the checkpoint.

## Remaining work

See [math-coverage-roadmap.md](math-coverage-roadmap.md). Rational inequalities, broader absolute equations, inverse/branch semantics, structured systems entry, more complex-number representations and general function analysis remain staged work. Recognition weights and grouping rules were not changed. Replace raw LaTeX correction with a visual mathematical editor later; keep LaTeX as an advanced option.
