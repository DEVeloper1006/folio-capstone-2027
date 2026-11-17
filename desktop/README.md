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

Desktop notebooks use persistent Chromium local storage under Electron's application data directory. Browser notebooks retain tab-scoped session storage. Browser data is not automatically imported into the desktop profile. React Query continues to hold the live editing state.

Browser API review:

- DOM selection, ranges, focus, keyboard events, ResizeObserver, MathLive custom elements and local fonts run in Electron's Chromium renderer.
- Clipboard reads/writes use the existing browser Clipboard API on the secure local protocol.
- `window.prompt()` was replaced with the shared dialog and field components for the focus-by-number command.
- Routing falls back to the bundled SPA shell. Assets and fonts are loaded locally through the protocol.
- Autocomplete uses IPC on desktop and the existing Vite proxy in browser development. Obsolete desktop requests are cancelled in the main process.
- Native edit menus retain copy, paste, undo and redo accelerators. External HTTP(S) links open in the default browser.

The renderer uses context isolation, process sandboxing and disabled Node integration. The main process validates IPC senders and request sizes. Native filesystem access is not exposed to notebook content.
