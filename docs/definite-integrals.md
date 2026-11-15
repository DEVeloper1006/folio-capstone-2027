# Integral review

Tap a row → check its rendered transcription → tap the checkmark → choose Integrate or Evaluate definite integral → review → Compute → Insert result.

## Full notation

Full notation is accepted directly: `\int_{-1}^{2} t^2\,dt` supplies variable t, lower −1 and upper 2, and returns exactly 3. `\int_0^{\pi} \sin t\,dt` supplies t, 0 and π and returns exactly 2. The recognized source is preserved; it should not be stripped by hand.

The review screen shows the variable and limits read from the expression. Edit recognition before acceptance if the transcription is wrong. For a separate calculation, expand Edit this calculation’s input and choose Edit parts separately; it pre-fills the function, variable and limits. Editing does not overwrite the accepted row.

For integrand-only input, enter the interval in the visible fields. Constant expressions can use the variable override under Details; otherwise the single variable is inferred. Blank required limits are errors. Unused/hidden parameters are ignored.

## Exact and approximate

Native polynomial arithmetic remains exact. The elementary path supports additional trig, rational, exponential and logarithmic cases when it can verify an antiderivative by simplifying its derivative minus the integrand to zero. Finite constants such as π and e can appear in limits. Definite integration uses F(upper)−F(lower), with no +C; reversed limits give a signed result.

A full indefinite integral supplies its differential and can be used with separately reviewed finite limits. A bounded integral is not silently treated as an antiderivative. Symbolically unresolved integrals offer a clear error; Numerical definite integral is a separate explicit option with ≈ output and an estimated error.

Improper integrals and unresolved domain/pole cases are rejected. Interval checks are conservative; additional singularities, branches or special-function cases may need splitting or another method. This does not cover every Calc 1 integral. See [full coverage and limitations](calc1-support.md).

## Source boundary

PolynomialIntegralInput retains the tested polynomial wrapper parser. The extended worker has a bounded mathematical tokenizer/AST for general function and integral notation. It recognizes the differential, binds one independent variable, and validates constant limits without executing user strings as code. Calculation engine/backend versions and resolved parameters are saved alongside the unchanged source expression.

The old PolynomialIntegrationView remains as legacy code; the primary row UI now routes through the unified workbench. Recognition model weights/grouping are unchanged.
