# Contributing to Folio

This guide covers setup, code patterns, and checking changes. Read [AGENTS.md](AGENTS.md) for the detailed repository rules. Keep this guide current when the stack, commands, or conventions change.

## Stack and setup

- React and strict TypeScript, with TanStack Start and TanStack Router.
- Vite for development and builds; Nitro for the production Node server.
- MathLive for editable LaTeX fields; plain CSS for styling.
- React state for the current notebook. Zustand is installed but is not currently used.
- pnpm for dependencies. Node.js and pnpm versions are not pinned yet.

From the repository root:

```bash
cd client
pnpm install
pnpm dev
```

Open <http://localhost:3000>. Run the remaining commands from `client/`.

### Isolated editor comparison

The optional [editor comparison](editor-comparison/README.md) runs separately on <http://127.0.0.1:3011/>. From `editor-comparison/`, run `npm install`, `npm run setup`, then `npm run dev`. It has its own dependencies and build; it compares native library defaults, labeled Folio and DesQuill configurations, Guppy's standard-LaTeX adapter, and three source-preview workflows. It includes fifty notation examples, custom input, and an optional source fallback for unsupported native imports. Changing its columns does not change the main app's editor. Run `npm run typecheck` and `npm run build` there to check comparison changes.

## Code patterns

- `src/routes/`: page components and the document shell.
- `src/components/`: React UI components, including the MathLive cell wrapper.
- `src/editor/`: public editor entry in `index.ts`, with `navigation/`, `structure/`, `commands/`, `mathlive/`, and `samples/` underneath.
- `src/styles.css`: application styles.

Use small functions with named exports and keep React components focused on rendering and lifecycle work. Use the existing `#/` alias for imports from `src/` and relative paths within a module.

Keep all custom movement and selection behavior in `src/editor/navigation/navigation-rules.ts`. Keyboard decoding, structure extraction, transition handling, and MathLive event handling have separate files in `navigation/`, `structure/`, and `mathlive/`. Unhandled actions fall back to MathLive; see the [navigation overview](README.md#navigation-experiment).

Navigation keeps the logical selection anchor separate from MathLive's visible range so reversing a whole-structure selection can return inside it. Vertical moves retain previous region positions until another interaction resets them. Keep these transitions in the existing editor modules and use MathLive's public element metadata and selection API; the React cell wrapper only installs and cleans up the integration.

`structure/selection-spans.ts` groups direct layout nodes into syntactic selection candidates without evaluating or rewriting the formula. Keep these ranges separate from term-jump spans in `structure/structure.ts`; selection growth and shrinking remain rules in `navigation/navigation-rules.ts`. Preserve complete calls, scripts, delimiter boundaries, and quantifier scopes, while retaining exact shrink history.

Expression commands use a local definition catalog, a replaceable asynchronous search function, a cell-local hook, and a presentation component. Keep aliases and one-level variants in `commands/expression-commands.ts`, ranking in `commands/expression-command-search.ts`, and insertion sessions in `commands/use-expression-commands.ts`. The menu edits only its own query until a command is accepted. Do not put search queries into the formula or rebuild MathLive when menu state changes. See [expression commands](README.md#expression-commands) for triggers and keyboard behavior.

The app uses SSR and browser hydration, without React Server Components. Load the editable MathLive implementation in the browser, as the existing cell wrapper does. Clean up editor instances and listeners when their component unmounts.

## Naming and documentation

- Follow [frontend naming patterns](FRONTEND_NAMING.md) for components, hooks, state, refs, and callbacks.
- Use `camelCase` for variables and functions; use descriptive verbs for functions and `is`, `has`, or `can` for boolean names when appropriate.
- Use `PascalCase` for React components, interfaces, and type aliases.
- Use `kebab-case` for handwritten source filenames, such as `latex-cell.tsx`. Keep framework-required filenames such as `__root.tsx`.
- Prefer concrete domain names such as `selection`, `anchor`, and `focus` over vague names such as `data` or `manager`.
- Start every handwritten source file with a purpose comment, and document every function, including callbacks. Describe concrete behavior and maintain comments when that behavior changes. See [AGENTS.md](AGENTS.md#documentation) for the full requirements and exceptions.
- Put documentation on separate lines above named declarations, including callbacks. Do not embed docstrings in calls or JSX. A short inline comment may follow code, never precede it on the same line. ESLint enforces standalone documentation; Prettier handles formatting.

## Tools and checks

| Tool                               | Purpose                                       | Command                             |
| ---------------------------------- | --------------------------------------------- | ----------------------------------- |
| Prettier + `prettier-plugin-jsdoc` | Format code and documentation                 | `pnpm format` / `pnpm format:check` |
| ESLint + `eslint-plugin-jsdoc`     | Check code quality and required documentation | `pnpm lint`                         |
| TypeScript                         | Check types                                   | `pnpm typecheck`                    |
| Vite / TanStack Start              | Verify the production build                   | `pnpm build`                        |
| Node's built-in test runner        | Run the one test file in each editor area except samples | `node --test src/editor/**/*.test.ts` |

Formatting uses a 300-character wrap width for code and JSDoc, two spaces, LF line endings, single quotes, no semicolons, and trailing commas. Cursor workspace settings enable Prettier on save and ESLint fixes; install the recommended Prettier and ESLint extensions.

**Test development is paused:** do not add or extend tests or install another test framework until Saad asks to resume. Existing tests remain available; there is no `pnpm test` script.

Before requesting review, run the relevant checks above. For editor behavior, also try the affected interaction in the browser, including nested expressions and Shift selection when applicable. Describe what changed, why, what you checked, and any remaining limitations. Documentation-only changes need a formatting check rather than an application build.

## Current scope and maintenance

- The home page is a navigation playground with 20 sample expressions. Movement behavior is experimental, not a final product specification.
- Cell contents live in memory and reset on refresh; there is no persistence layer yet.
- Preserve unrelated changes and the source documents in `.mac/`.
- Let pnpm update its lockfile and tooling regenerate `src/routeTree.gen.ts`; do not hand-edit generated output or dependencies.
- Keep changes focused and explain the reason for framework changes, new dependencies, or new interaction conventions in the review description.
