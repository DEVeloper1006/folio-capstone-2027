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

Rules run in registration order and target the nearest matching node. Returning `undefined` defers to another rule. Unhandled actions fall back to MathLive. Add new node-specific behavior to the rule registry rather than the DOM key handler.

Keyboard navigation adapts [DesQuill's movement and selection behavior](https://github.com/desmosinc/mathquill), using its visual-arrow policy (`leftRightIntoCmdGoes: 'up'`):

- Left/right arrows enter numerators and superscripts, then exit the containing structure horizontally. Up/down enters adjacent structures or moves between related regions, choosing a nearby horizontal position and remembering positions for the return trip.
- Shift-left/right selects whole constructs across region boundaries. Reversing restores the original inner selection. Shift-up/down selects toward the current region's start/end, expanding outward on another press.
- Home/End targets the current region; Control-Home/End targets the expression. Shift extends the selection.
- Tab/Shift-Tab and Escape/Shift-Escape exit a region forward/backward. Matrix and cases cells visit sibling cells; up/down moves between rows in the same column.
- Existing Option/Alt term jumps, structure entry/exit, and selection growth/shrinking remain available in the on-page movement guide.

This extends the existing modules without adding dependencies or importing DesQuill's runtime. MathLive still handles typing, undo, and mouse selection. It uses the documented [`getElementInfo()` and selection API](https://mathlive.io/mathfield/api/), rather than accessing MathLive's private model. Matrix row navigation falls back to MathLive when cell coordinates cannot be recovered reliably. Integrands and operator bodies remain ordinary rows rather than semantic arguments; this is not full Desmos interaction parity.

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
