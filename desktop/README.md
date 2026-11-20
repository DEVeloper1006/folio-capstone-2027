# Folio desktop

This worktree adds an Electron wrapper around the existing React notebook. Desktop builds use TanStack Start's SPA mode and serve bundled assets at `folio://app/`. Editing works without the Vite server or a Python backend.

From the repository root, run:

```sh
pnpm --dir client install --frozen-lockfile
npm --prefix desktop ci
npm --prefix desktop run build
npm --prefix desktop start
npm --prefix desktop run package
```

Packaging produces an application for the current OS and CPU under `desktop/release/`. Release artifacts and renderer bundles are ignored by Git. Electron's first launch may download its binary. An already-downloaded official release ZIP can be supplied through `ELECTRON_ZIP_DIR` when packaging. Distribution signing, notarization and automatic updates need a separate release setup.

For autocomplete, launch Electron with `OPENROUTER_API_KEY` exported in the environment. The main process reads the key and calls OpenRouter through a restricted preload bridge. The key is never copied into the renderer or packaged application. Launching from Finder generally does not inherit a shell-exported key. An application settings flow for storing credentials is still future work. A missing key leaves editing available and returns an unavailable response for suggestions.

Desktop notes live in `~/Documents/Folio` initially, as Markdown files and real subfolders. **Roots → Open folder…** selects another local Markdown folder; **Show folder** reveals the current location. Hidden `.folio/` metadata preserves block identities, nesting, undo history, and editable graph views; PNG figures live in `assets/`. Keep these folders with the Markdown files. Folio identity comments must remain unchanged when editing its blocks in another editor. Plain `.md` files without Folio metadata open as editable text blocks. External edits reload when Folio regains focus or through **Roots → Reload**; stale writes are refused. The first launch migrates the old desktop notebook without deleting Chromium storage and keeps a migration snapshot. Browser previews still use tab-scoped session storage. React Query holds live editing state.

## Settings

Open **Settings → Settings** or press **Cmd+,** (Ctrl+, with default bindings). The searchable settings page has Appearance, Editor, Math help, and Keyboard shortcuts categories. Changes save automatically; text fields save on blur or Enter. Custom subjects use labeled guidance and notation fields with an explicit Save subject action.

Click a keybinding to record a replacement. Unmodified Escape cancels; Backspace or Delete disables it; Reset restores the default. Duplicate bindings are rejected before saving. Preferences still persist atomically in Electron's user-data `settings.json` (normally `~/Library/Application Support/Folio/settings.json` on macOS), retaining existing preferences and external-edit conflict protection. No JSON editing is required.

Invalid configuration is shown for repair and does not replace the running settings. On startup, built-in defaults remain active until the file validates. Saving a stale draft is rejected rather than overwriting external changes. Drafts remain when moving between settings and pages, but save them before quitting. Native text-editing shortcuts and block-handle arrow keys remain platform controls. Browser previews use local storage rather than a disk file. Document-specific page layout and graph expressions remain saved with their pages.

## Managing blocks

Each document block has a drag handle and an action menu on its right. Drag onto another block's upper or lower edge to move before or after it; drop in its center to nest inside it. The drop indicator names the destination before release. Moving a parent carries its nested blocks, including graphs. The menu also offers **Move up**, **Move down**, **Nest under previous block**, and **Move out one level**. On the focused drag handle, arrow keys perform those same operations (up/down for order, right/left for nesting).

**Delete block** removes the whole subtree. **Undo delete** restores the last deleted group, and can be used repeatedly. Deleted groups persist with the page across app restarts. If their former neighbor or parent has moved, restoration uses the surviving hierarchy; if neither remains, the group returns at page end. This is block deletion undo, not a replacement for an editor's text undo.

## Interactive graphs

Create a page from the sidebar, name it in the document, then choose **Write a note**, **Add math**, or **Explore a graph**. The sidebar's **Search** button (⌘K) searches page titles and commands; use the arrow keys and Enter to choose a result.

The document is the main workspace. Its **Graph** action opens a tool panel on the right, with independent scrolling on wider windows and an overlay on small windows. Close the panel with its × button. The page title stays visible in the toolbar. Settings includes a **Back to page** action.

Pan, zoom, or rotate the plot, then choose **Insert view**. Folio appends an image of that exact view to the document and closes the panel. Each figure keeps its equations, sliders, axes, camera, and aspect ratio. Click the figure or **Edit graph** to reopen it; **Update view** replaces that figure in place. Closing an edit without updating leaves the inserted figure unchanged. Inserted figures are independent of each other and of the page's scratch graph. Images and graph source save together through the existing page writer; storage/export errors leave the document unchanged.

In Graph, type into **Your first equation** and press Enter or **Plot**. Once added, edits to an equation update the plot live. Each page saves its own graphs alongside its notebook cells. The input for the next equation is a draft until submitted; switching pages or closing the graph discards that unsubmitted draft.

- **2D:** enter `y = a*sin(x)` for a curve, or `x^2 + y^2 = r^2` for an implicit equation.
- **3D:** enter a surface such as `z = a*sin(x)*cos(y)`. Drag to orbit and scroll to zoom.
- Free lowercase names such as `a` and `r` create sliders. Edit the value directly, or expand **Slider settings** to set minimum, maximum and step. Angles use radians.
- Add up to six expressions per dimension; the Show checkbox hides a trace without removing its expression. 2D and 3D retain separate expression lists and share parameter values and domain bounds.
- In 2D, drag to pan and scroll to zoom. In 3D, drag to rotate. **Reset** restores the view. Expand **Plot range** to change the sampled region. Zooming alone does not sample new coordinates outside that range.

Graphs use MIT-licensed [Plotly.js](https://github.com/plotly/plotly.js) (the strict, CSP-compatible bundle) and Apache-2.0-licensed [math.js](https://mathjs.org/). Their license files ship with the desktop renderer. Plotly loads when Graph opens. Graphing works offline and needs no API key or model. The expression parser accepts scalar arithmetic and the functions listed under **Syntax & limits**; it rejects scripts, assignments, accessors and arrays.

This is a numerical graph workspace, not a symbolic solver or a full Desmos/GeoGebra replacement. Curves use 1,001 samples, implicit equations a 121×121 grid, and surfaces a 65×65 grid. Undefined real values leave gaps. Narrow features and discontinuities can be missed; adjust the domain to inspect them. Inequalities, parametric curves and implicit 3D solids are not supported.

## Desktop integration

Browser API review:

- DOM selection, ranges, focus, keyboard events, ResizeObserver, MathLive custom elements and local fonts run in Electron's Chromium renderer.
- Clipboard reads/writes use the existing browser Clipboard API on the secure local protocol.
- `window.prompt()` was replaced with the shared dialog and field components for the focus-by-number command.
- Routing falls back to the bundled SPA shell. Assets and fonts are loaded locally through the protocol.
- Autocomplete uses IPC on desktop and the existing Vite proxy in browser development. Obsolete desktop requests are cancelled in the main process.
- Native edit menus retain copy, paste, undo and redo accelerators. External HTTP(S) links open in the default browser.

The renderer uses context isolation, process sandboxing and disabled Node integration. The main process validates IPC senders and request sizes. Native filesystem access is not exposed to notebook content.

## Contextual math help

Select a notebook block. The thin bottom status bar shows its subject; **Auto** detects the subject, and a manual selection overrides detection for that problem section. **Hint** inside the selected block shows one short, dismissible hint. The status bar has only subject controls; no help buttons, next-step form, or notation drawers. Requests include the whole current page, with the current problem and selected block identified, including graph equations but not image bytes. Context is automatic and cannot be edited independently. Pages above the 20,000-character context limit are rejected without truncation. Hints remain conceptual and never insert or replace notebook content. Editing the page or switching blocks invalidates pending proposals. Cmd/Ctrl+Z restores a deleted block when focus is outside a text or math editor; native text undo remains in editors.

Math help runs through local Ollama at `127.0.0.1:11434`; start Ollama with an installed model. Choose the installed model in **Settings → Math help → Local model** (default `qwen3.5:4b`). The same category offers the default subject and automatic subject detection; explicit section choices remain unchanged.

Custom subjects and notation templates can be edited in `math.modes` in the settings file. Templates require exactly one `#1` argument; unsupported LaTeX and duplicate ids are rejected. Built-in subjects are general, algebra, calculus, linear algebra, proofs/discrete math, probability/statistics, and geometry/trigonometry. Model-generated hints still need human review. The browser preview does not offer the desktop local-model bridge.

## Organization and export

The sidebar supports nested folders, moving pages/folders through their menus, and expandable page headings for exact in-document navigation, including duplicate heading titles. Removing a folder promotes its contents rather than deleting pages.

**Export** saves the current page as PDF or Markdown (with a companion graph-image folder). **Back up all Roots…** saves every page, folder relationship, graph source/view, and block record in a `.folio` file. **Roots → Restore backup…** restores into a new folder and leaves the old root untouched. App-wide settings remain in the separate `settings.json`; copy it separately to transfer custom modes/preferences to another machine. Folder organization is journaled; an interrupted write rolls back on the next load. Folio does not implement Obsidian plugins, wikilink rewriting, or cloud sync.
