# Folio

TanStack Start application in `client/` with a MathLive editor. The home page starts with 20 editable expressions for trying cursor movement. State is kept in memory; refreshing restores the examples.

## Installation

```bash
cd client
pnpm install
```

Requires Node.js and pnpm. Run the commands below from `client/`.

## Development

```bash
pnpm dev
```

The dev server runs at http://localhost:3000 with the standard Vite and TanStack Start setup, including SSR.

## Checks

```bash
pnpm typecheck
pnpm lint
pnpm format:check
pnpm format
node --test src/editor/*.test.ts
```

The tests use Node's native TypeScript support.

## Navigation experiment

These interactions are experimental, not final product requirements.

1. `client/src/editor/navigation-actions.ts` converts keyboard events into named actions.
2. `client/src/editor/structure.ts` identifies layout nodes and editable regions using MathLive's public metadata. It classifies fractions, scripts, operator limits, roots, and matrix/cases cells.
3. `client/src/editor/navigation-rules.ts` contains all custom movement and selection rules, including structural arrows, region boundaries, term jumps, and selection growth/shrinking.
4. `client/src/editor/navigation-transition.ts` applies rule results and retains the original selection anchor and vertical return positions between related actions.
5. `client/src/editor/navigation.ts` reads the field, dispatches actions, and writes the visible selection through MathLive's public API. Pointer input, formula edits, and blur reset navigation history.

Selection growth uses `client/src/editor/selection-spans.ts` to recover syntactic units within each editable region: complete function calls, scripted bases, arithmetic expressions, logical clauses, and quantified bodies. For example, Shift-Option-Up inside `R(y)` grows through `y`, `R(y)`, its negation, the conjunction, and the enclosing quantified expression. Shift-Option-Down restores the exact previous ranges, including the original cursor or backward selection. At a boundary, growth prefers the expression ahead in the current region. These ranges are separate from term-jump spans, so Option-Left/Right keeps its existing behavior.

This is syntax-based selection rather than mathematical evaluation. It preserves incomplete input and uses layout regions and balanced delimiters as boundaries. Conventional operator precedence and common quantifier declarations are supported; ambiguous notation is not assigned a mathematical meaning or rewritten.

Rules run in registration order and target the nearest matching node. Returning `undefined` defers to another rule. Unhandled actions fall back to MathLive. Add new node-specific behavior to the rule registry rather than the DOM key handler.

Keyboard navigation adapts [DesQuill's movement and selection behavior](https://github.com/desmosinc/mathquill), using its visual-arrow policy (`leftRightIntoCmdGoes: 'up'`):

- Left/right arrows enter numerators and superscripts, then exit the containing structure horizontally. Up/down enters adjacent structures or moves between related regions, choosing a nearby horizontal position and remembering positions for the return trip.
- Shift-left/right selects whole constructs across region boundaries. Reversing restores the original inner selection. Shift-up/down selects toward the current region's start/end, expanding outward on another press.
- Home/End targets the current region; Control-Home/End targets the expression. Shift extends the selection.
- Tab/Shift-Tab and Escape/Shift-Escape exit a region forward/backward. Matrix and cases cells visit sibling cells; up/down moves between rows in the same column.
- Existing Option/Alt term jumps, structure entry/exit, and selection growth/shrinking remain available in the on-page movement guide.

This extends the existing modules without adding dependencies or importing DesQuill's runtime. MathLive still handles typing, undo, and mouse selection. It uses the documented [`getElementInfo()` and selection API](https://mathlive.io/mathfield/api/), rather than accessing MathLive's private model. Matrix row navigation falls back to MathLive when cell coordinates cannot be recovered reliably. Integrands and operator bodies remain ordinary rows rather than semantic arguments; this is not full Desmos interaction parity.

## Expression commands

Type `/` in an empty editable region or over a selected placeholder to open the local expression menu. Slash after existing math keeps MathLive's fraction entry. The query stays in the menu and never enters the formula; Escape, Space on an empty query, or leaving the menu cancels without editing the expression. Spaces inside queries are supported.

Use Up/Down to select, Right to browse one level of variants, Left to return, and Enter to insert. Parents and children are independently searchable: `int` ranks Integral first, while `contour integral` directly selects that variant. Mouse selection and variant buttons are also available. Insertion expands a LaTeX template into editable math and selects its first placeholder; Tab/Shift-Tab selects remaining unfilled placeholders before ordinary region navigation resumes. MathLive retains its normal undo behavior.

- `client/src/editor/expression-commands.ts` owns the local catalog, aliases, and templates. The initial groups cover fractions, radicals, big operators, and integrals. These are insertion templates, not persistent macro references.
- `client/src/editor/expression-command-search.ts` exposes an asynchronous request/result contract with deterministic keyword search. Search is local; no network calls, persistence, or extra dependencies are introduced.
- `client/src/editor/use-expression-commands.ts` owns each cell's command session and ignores stale search responses. The provider can be replaced without changing the menu.
- `client/src/components/expression-command-menu.tsx` renders the query, results, and variants beneath the active cell.

MathLive's public [insertion API](https://mathlive.io/mathfield/api/#mathfieldelementinsert) handles expansion and placeholder selection. Existing mathematical movement rules remain in `navigation-rules.ts`; the command menu owns navigation only while its search input is focused.

## Production

```bash
pnpm build
pnpm start
```

`pnpm build` uses TanStack Start’s standard Vite production build. `pnpm start` serves the generated Node server at `client/.output/server/index.mjs`.

## Repository conventions

[CONTRIBUTING.md](CONTRIBUTING.md) covers setup, the stack, code patterns, naming conventions, and checks before review.

[AGENTS.md](AGENTS.md) defines the source documentation and working rules. Cursor loads them through `.cursor/rules/repository-conventions.mdc`.

Prettier formats source and configuration files, with `prettier-plugin-jsdoc` wrapping documentation comments. ESLint checks code quality and requires file overviews and descriptions for every function, including callbacks. Cursor's workspace settings enable Prettier on save and ESLint fixes, using the locally installed packages in `client/`.

Every handwritten source file starts with a purpose comment, and documentation changes with the behavior it describes. Generated files, lockfiles, binary documents, and strict JSON retain their native formats. The current instruction is not to add tests.
