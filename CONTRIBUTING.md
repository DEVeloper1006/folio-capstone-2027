# Contributing to Folio

This guide covers setup, code patterns, and checking changes. Read [AGENTS.md](AGENTS.md) for the detailed repository rules. Keep this guide current when the stack, commands, or conventions change.

## Stack and setup

- React and strict TypeScript, with TanStack Start and TanStack Router.
- Vite for development and builds; Nitro for the production Node server.
- MathLive for editable LaTeX fields; plain CSS for styling.
- Plotly.js's strict bundle for interactive 2D/3D graphs; math.js for bounded scalar expression parsing and evaluation. Both run locally without a graphing service or AI model.
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

## iPad app and research

The [iPad guide](ipad/README.md) covers `ipad/app/`, Xcode builds and staging validated local recognition assets. Research prototypes live in `research/folio-ipad-labs/` and have separate dependencies; they do not replace `client/`. Preserve imported baseline tests; the pause on adding or extending tests still applies. Run platform builds from their own folders and keep model exports, notebook data and local backups out of Git.

## Code patterns

- `src/routes/`: page components and the document shell.
- `src/routes/workspace.css`: page toolbar, sidebar refinements, direct writing actions, and the optional graph tool panel. Reuse the existing page writer and command dispatcher; layout changes must preserve cell and graph data.
- `src/notebook/notebook-blocks.ts`: subtree operations on the ordered cell list. Optional `depth` is a preorder level (old cells are level zero). Every move includes descendants, rejects self/descendant destinations, and preserves content and stable ids. Graph updates and sibling insertion must retain depth. Deleted subtrees and restore anchors persist in `Page.deletedBlocks`; restore must not roll back newer text edits.
- `src/components/`: React UI components, including the MathLive cell wrapper.
- `src/editor/`: public editor entry in `index.ts`, with `navigation/`, `structure/`, `commands/`, `mathlive/`, and `samples/` underneath.
- `src/styles.css`: application styles.
- `src/graph/`: page-owned graph state and sampling, shared form controls, and the browser-only Plotly lifecycle. Keep expression validation in `graph-model.ts`. Graph cells store a PNG snapshot with editable graph source and the captured axes/camera/aspect ratio. Capture from the live renderer; save image and source atomically through the notebook page writer. Editing an inserted graph stays local until Update view.
- 3D capture validates Plotly's rendered scene camera because the public layout can lag the last scroll frame. Recheck this adapter when upgrading Plotly; an incompatible renderer must report an error rather than insert a different viewpoint. Clone saved layouts before handing them to Plotly, which mutates layout objects.

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

| Tool                               | Purpose                                                  | Command                               |
| ---------------------------------- | -------------------------------------------------------- | ------------------------------------- |
| Prettier + `prettier-plugin-jsdoc` | Format code and documentation                            | `pnpm format` / `pnpm format:check`   |
| ESLint + `eslint-plugin-jsdoc`     | Check code quality and required documentation            | `pnpm lint`                           |
| TypeScript                         | Check types                                              | `pnpm typecheck`                      |
| Vite / TanStack Start              | Verify the production build                              | `pnpm build`                          |
| Node's built-in test runner        | Run the one test file in each editor area except samples | `node --test src/editor/**/*.test.ts` |

Formatting uses a 300-character wrap width for code and JSDoc, two spaces, LF line endings, single quotes, no semicolons, and trailing commas. Cursor workspace settings enable Prettier on save and ESLint fixes; install the recommended Prettier and ESLint extensions.

**Test development is paused:** do not add or extend tests or install another test framework until Saad asks to resume. Existing tests remain available; there is no `pnpm test` script.

Before requesting review, run the relevant checks above. For editor behavior, also try the affected interaction in the browser, including nested expressions and Shift selection when applicable. Describe what changed, why, what you checked, and any remaining limitations. Documentation-only changes need a formatting check rather than an application build.

## Current scope and maintenance

- The home page is a navigation playground with 20 sample expressions. Movement behavior is experimental, not a final product specification.
- Notebook pages persist as Markdown files in a local Roots folder on Electron; browser previews use session storage. `desktop/notebook.cjs` journals filesystem changes, retains Folio metadata in `.folio/`, and refuses stale writes over external edits. `notebook-storage.ts` validates migration and backup data and is bundled for Electron during the desktop build. Sidebar folders and heading outlines reuse the page store; PDF/Markdown export uses native save dialogs.
- Preserve unrelated changes and the source documents in `.mac/`.
- Let pnpm update its lockfile and tooling regenerate `src/routeTree.gen.ts`; do not hand-edit generated output or dependencies.
- Keep changes focused and explain the reason for framework changes, new dependencies, or new interaction conventions in the review description.

## Electron desktop

The `desktop/` package builds the shared frontend in SPA mode and packages it with Electron. See [desktop/README.md](desktop/README.md) for setup commands, storage behavior, autocomplete credentials and platform limitations. Browser development retains the existing Vite workflow.

Settings use searchable graphical controls and the shared shortcut recorder (`client/src/settings/`), backed by one validated JSON document. Save complete edits through the existing writer; keep incomplete text and custom-subject drafts local. Desktop reads and atomically replaces the fixed user-data `settings.json` through narrow preload IPC in `desktop/settings.cjs`; expected-source checks reject stale writes. External saves reload through the same validator. Apply only validated preferences to the existing theme tokens and shortcut cache. Keep document content and per-page display metadata out of global settings. Browser previews persist the same document in local storage.

Math assistance lives in `client/src/math-help/`. Keep subject guidance and validated single-argument notation separate from model transport. The desktop bridge sends bounded JSON requests only to local Ollama; the settings file owns model selection and the custom mode library. Hints never insert computed steps, proposals require explicit acceptance, and context changes invalidate pending results. Preserve these contracts when replacing the model.

Subject selection lives in the bottom status bar; a single Hint button and dismissible hint live inside the selected block. Subject detection is automatic unless a section has a manual choice. Requests include the complete current page with selected problem/block markers; oversized context is rejected, never silently truncated. Keep hint responses conceptual. The normal writing flow has no step-input panel, notation drawer, or mode-generation controls; custom subjects remain editable under Settings → Math help.
