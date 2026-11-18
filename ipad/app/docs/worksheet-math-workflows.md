# Worksheet math: notation, problem scope and visible computation

## Evidence and design decisions

The implementation was informed by these primary textbook sections (read November 18, 2026):

- [OpenStax Calculus 1 §3.2, The Derivative as a Function](https://openstax.org/books/calculus-volume-1/pages/3-2-the-derivative-as-a-function): students introduce a function, then write prime, Leibniz or operator notation on later lines. `f(x)=x^2-2x` gives `f'(x)=2x-2`. These denote functions and derivatives, not multiplication by letters f or d.
- [OpenStax Calculus 1 §5.4, Integration Formulas and the Net Change Theorem](https://openstax.org/books/calculus-volume-1/pages/5-4-integration-formulas-and-the-net-change-theorem): worked solutions rewrite an integrand, find an antiderivative, then apply bounds. The integration differential selects the bound variable; indefinite and definite integrals have different outputs and constant rules. A worksheet may define `f(x)` above a later integral of `f(x)`.
- [OpenStax Calculus 3 §4.3, Partial Derivatives](https://openstax.org/books/calculus-volume-3/pages/4-3-partial-derivatives): partial differentiation selects one independent variable and holds the others constant. For `f(x,y)=x^2-3xy+2y^2-4x+5y-12`, partials are `2x-3y-4` and `-3x+4y+5`. This is a distinct operation from ordinary one-variable differentiation and from solving a differential equation.

Product inference from these examples: store the statement's meaning and function signature before choosing an operation, retain the original transcription, protect bound variables during substitution, and preserve the source rows used by every computation. Textbook examples establish conventions; they do not validate handwriting accuracy, automatic grouping or every CAS result.

## Architecture

`WorksheetMathNotation` classifies function/scalar definitions, equations, ordinary expressions, integrals and explicit ordinary/partial derivative requests. The SwiftData `Step.problemASTJSON` stores the exact input, semantic fields, function parameters and optional native polynomial expression AST. The calculus backend continues to parse supported elementary expressions into its own whitelisted tree in a fresh worker. No input is evaluated as code, and no recognition-model retraining is implied.

`ProblemContextMathService.refresh` derives scopes independently of whether the native polynomial solver supports a row. A calculus row no longer loses its scope simply because it is not a polynomial equality. Separate column lanes retain independent histories, rather than alternating page order accidentally joining both columns. Numbered questions, whitespace gaps, unread/prose boundaries, repeated definition names, definitions after a target and explicit separation corrections start fresh scopes. Function redefinition with a different formal parameter still starts a new scope because identity is the function name.

`plan` resolves only earlier definitions in the selected stored group. Used definitions must be accepted. Function parameters are bound, protected while resolving external references, then replaced by actual arguments; calculus variables are protected from scalar substitution. Partial requests also protect the function's other independent parameters. Function expansion currently uses bounded flat-call templates and protected symbol-token replacement, then reparses the expanded input through the existing solver AST. It does not claim a complete general function-call AST interpreter. Expansion has depth, size and work limits and rejects cycles. Function calls with unresolved definitions produce a recoverable error rather than being intentionally coerced into multiplication.

The workbench and direct contextual action share this plan. Full group source manifests are captured before asynchronous execution and validated again before save. Changed source revisions, ink, group membership or order invalidate the result. Matrices continue through their independent service; problem inference does not replace notebook segmentation or PencilKit.

## Visible action and result

The earlier contextual action saved answers under a collapsed result disclosure and offered no success feedback. The direct action now has a computing state, cancellation, immediate plain-text output, automatically expanded result cards and errors beside the action. Repeated computation can reuse the stored answer but still reveals it. For standalone existing workflows the workbench remains available; choosing another supported operation uses the same reviewed source.

## Supported paths and explicit limits

| Written workflow | Behavior |
| --- | --- |
| `t=10`, `y=2x+11`, `t+6y=15` nearby | Verify transcriptions/sources, solve the substituted linear equation: `x=-61/12`. |
| `f(x)=x^2-3x` | Function declaration; differentiate or choose Antiderivative in the workbench. Expected antiderivative `x^3/3-3x^2/2+C`. |
| `f(x)=x^2-2x`, then `f'(x)` or `f'x` | Resolve only this problem's f, differentiate with respect to x. Double-prime requests select the second derivative. |
| `y=x^2`, then `dy/dx` or `\frac{dy}{dx}` | Resolve the prior y definition; ordinary derivative request. |
| `d/dx(x^3)` or `\frac{d}{dx}(x^3)` | Explicit derivative operator applied to the expression. |
| `f(x)=x^2`, then `\int f(x) dx` | Expand the same-scope f before invoking the integration backend. |
| `f(x,y)=x^2-3xy+2y^2-4x+5y-12`, then `∂f/∂x` or `\frac{\partial f}{\partial x}` | Explicit partial derivative, holding other independent variables constant. |
| `z=x^2+y^2`, then `∂z/∂x` | Resolve z's expression and compute the partial with respect to x. |
| Bare `dy` | Incomplete differential; requires an integral or relation, never deliberately interpreted as d times y. |
| A derivative equality such as `f'(x)=2x`, or `dy/dx=y` | Stored as worksheet content but not a general ODE solver or proof of a student's step. Unsupported execution is rejected. |

Current limits: function arguments in contextual calls must be flat expressions (nested-parenthesis calls may need rewriting); Latin one-letter names/parameters; one or two prime marks; first-order explicit partial notation; elementary backend/domain limits still apply. Indexed functions, mixed/higher partials, arbitrary differential equations, symbolic-bound integration, arbitrary systems, complete proof checking and natural-language question interpretation are not universal supported operations. A prime or partial marker must not be silently dropped to make an input parse.

Automatic context remains a heuristic: two unnumbered exercises with the same symbols and no visual separation cannot always be distinguished from related working. The source review and **Separate here** correction remain necessary for those cases. No claim of zero interference is made from layout alone.

## Manual interaction and regression cases

1. Tap Verify & Solve on a supported grouped equation. Require visible output immediately and an expanded result card, including after tapping twice. A missing-source/save error must be visible beside the action.
2. Put the motivating scalar problem and a second problem redefining t and y on the same sheet. Each result must use only its own source summary. Repeat with numbered questions, a large gap and two columns, including interleaved vertical positions.
3. Compute a result, edit/delete a used definition, and confirm it becomes outdated. Change a definition in another group and ensure the first problem's answer remains current.
4. Work through each supported notation row above. Reopen and verify the interpretation and stored source manifest persist; an unaccepted definition must prevent execution.
5. In a separate exercise redefine `f(t)` after `f(x)`. Confirm the new declaration starts a fresh scope and the old definition is not inherited.
6. Verify direct partial requests select the written variable and ordinary derivative operations continue rejecting accidental multivariable input.
7. Try bare dy, a missing f definition, cyclic definitions, malformed differentials and an ODE. Require an explicit correction message and preserved source ink, without guessed arithmetic.
8. Recheck standalone calculus workbench operation changes, recognized bounds, result insertion/movement/removal, cancellation and notebook reopen.

No automated test source was added or extended while the repository pause remains in effect. Existing automated checks and manual execution evidence are recorded in `problem-context-checkpoints.md`; direct worksheet UI coverage must be stated separately from CAS coverage.
