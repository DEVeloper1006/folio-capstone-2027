# Folio

A local-first mathematics workspace. Write math, keep explanations beside it, transform expressions without overwriting earlier steps, and export the result.

## Native Mac prototype

From this experiment directory:

```sh
npm install
./scripts/setup-local-ocr
./scripts/run-native
```

The native app uses a loopback-only TexTeller worker and the included Grade 12 LoRA adapter. It preserves original strokes, offers draft recognition and alternatives, and requires review before acceptance. The Examples gallery contains 60 notation references. See [native setup and tests](native/README.md) and [training methodology](training/k12/README.md).

Mac inference and rendering were tested. iPad PencilKit source is included but has not been compiled or device-tested. The trained adapter is in `models/grade12`; credentials, user notebooks, downloaded datasets, and generated benchmark artifacts are not included.

## Run the browser prototype

Requires Node.js 22+, npm, Python 3.11+, and [uv](https://docs.astral.sh/uv/).

```sh
npm install
uv sync --frozen
./start
```

Open **http://127.0.0.1:5174**. The local API runs on port 8001. Both servers bind to loopback, not your network. `npm run dev` is an equivalent launcher.

Port 5174 is intentional; another service was using 5173 on the development machine.

If your managed npm wrapper reports that it cannot find npm, set `TEC_NPM_BIN_DIR` to the directory containing the actual Node installation's npm binary. This is a machine-specific setup issue, not a Folio dependency.

For a single-server production build:

```sh
npm run build
uv run --frozen uvicorn server.app:app --host 127.0.0.1 --port 8001
```

Open http://127.0.0.1:8001. Stop the development API first if it already occupies that port. Browser storage is specific to an origin: use a `.folio` export to transfer documents between the development and production URLs.

## What works

- Multiple local documents, search, renaming, automatic saving, and undo/redo.
- Structured keyboard math through MathLive: fractions, roots, powers, subscripts, matrices, integrals, and unfinished expressions.
- Explanatory text and section headings, independently editable step copies, step reordering, and alternative document copies.
- Pen, mouse, and touch input stored as vector strokes. Rectangle selection, movement, erasure, and selected-stroke duplication.
- SymPy commands: `/rref`, `/matmul`, `/derivative`, `/integral`, `/simplify`, `/expand`, `/factor`, `/substitute`, `/check`, and `/rowop`.
- Explicit row swaps, nonzero row scaling, and addition of a rational multiple of another row. The operation is recorded with the result.
- A preview before inserting any computed result. Original expressions and ink are preserved.
- Per-step export inclusion, PDF through the browser print dialog, raw LaTeX, and portable `.folio` files.
- Optional Gemini handwriting transcription and selected-step feedback. Both require consent before sending data.
- Responsive desktop and small-screen layouts, keyboard commands, and a document outline.

The example linear system reduces to **x = 2, y = 1, z = 1**. Select its augmented matrix, choose **Row reduce**, calculate, and insert the result.

### Keyboard

| Action                   | Shortcut                  |
| ------------------------ | ------------------------- |
| Command menu             | Cmd/Ctrl K                |
| Duplicate selected step  | Cmd/Ctrl Shift D          |
| Undo                     | Cmd/Ctrl Z                |
| Redo                     | Cmd/Ctrl Shift Z          |
| Download editable backup | Cmd/Ctrl S                |
| Export preview           | Cmd/Ctrl P                |
| Another math step        | Enter inside a math field |

Inside a math field, `/` makes a fraction, `^` makes an exponent, and arrow keys navigate the expression. An empty field's `/` opens the command menu. Use **View LaTeX** for direct source editing.

## Optional Gemini connection

```sh
cp .env.example .env
```

Set `GEMINI_API_KEY` in `.env`, then restart the API. The default model is `gemini-2.5-flash`; `GEMINI_MODEL` can select another compatible Gemini model. Do not commit `.env`.

- Recognition sends only the selected ink image. Users correct and accept the transcription before insertion.
- Feedback sends only the selected step and the question, not the document collection.
- API keys remain on the server. Requests go directly to Google's Gemini API and may incur charges under that account.
- No request is made without checking the consent box. No training or background document upload occurs.
- Without a key, the UI says recognition is disconnected and offers manual transcription. Symbolic commands still work.

Live Gemini calls were not exercised during development because no key was configured. The provider boundary, review flow, error handling, consent, and late-response protection are tested with mocked responses.

## Data and correctness

Documents live in browser `localStorage`, with a 350 ms save debounce and a page-close flush. This is not cloud sync or a backup service. Download `.folio` files before clearing browser data or changing machines. Storage failures are visible; the current document remains in memory and can be downloaded. A conflicting tab pauses saving instead of silently overwriting the other tab's work.

The versioned `.folio` format contains original LaTeX, text, stroke coordinates, ordering, and export flags. Imports are validated and receive new identifiers, so they cannot overwrite an existing document. MathJSON is produced on demand at the computation boundary. Keeping original LaTeX allows unfinished expressions to survive saving without inventing a valid syntax tree.

The computation path is:

```text
MathLive LaTeX -> Compute Engine MathJSON -> bounded whitelist adapter
             -> SymPy worker -> LaTeX preview -> explicit insertion
```

No Python `eval`, string `sympify`, arbitrary execution, or LLM arithmetic. Each computation has an 8-second wall-clock timeout, a CPU limit on supported systems, and bounded input size and expansion complexity. Matrices are limited to 8 by 8. Scalar commands support arithmetic, common functions, and simple named variables. Unsupported syntax returns an error without changing the document.

“Equivalent” means symbolic equivalence where both expressions are defined, not proof of identical domains. Simplification may cancel factors, and integration returns an indefinite integral with an arbitrary constant. Formal proofs, arbitrary piecewise expressions, assumptions, and all possible special functions are not supported.

## Tests

```sh
npm test
npm run build

# With npm run dev running in another terminal:
npx playwright install chromium
npm run test:e2e
npm run test:a11y
node scripts/smoke.mjs
# test:e2e also runs the mocked AI flow and real keyboard-input checks.
```

Tests cover exact matrix and calculus results, invalid and excessive inputs, API boundaries, portable-file validation, local persistence, export exclusion, editing, duplication, undo/redo, ink selection, correction, and mobile navigation. `scripts/smoke.mjs` writes screenshots and a sample PDF to `artifacts/`. The accessibility script checks the initial workspace against automated WCAG A/AA rules; it is not a claim of complete accessibility conformance.

## Project map

| Path                 | Responsibility                                           |
| -------------------- | -------------------------------------------------------- |
| `src/App.tsx`        | Workspace, editing, commands, consent, and export UI     |
| `src/MathEditor.tsx` | MathLive editing, lazy MathJSON parsing, KaTeX preview   |
| `src/InkCanvas.tsx`  | Vector ink, selection, movement, erasure, PNG capture    |
| `src/model.ts`       | Versioned documents, import validation, LaTeX export     |
| `server/engine.py`   | Bounded MathJSON adapter and deterministic commands      |
| `server/app.py`      | Local API, timed worker processes, optional Gemini calls |

## Deliberate limits

The browser and native Mac prototypes are separate applications with different document formats. Chromium desktop and emulated mobile browser interactions were tested; Safari and Apple Pencil hardware were not. The native app includes a trained recognition adapter with limited regression measurements, not a general handwriting accuracy guarantee. There is no cloud collaboration or automatic cross-device sync. Alternative solutions are independent document copies, not a mergeable branch graph.

PDF export uses the browser's **Save as PDF** option. Turn off browser headers and footers. Handwriting is preserved in PDF and `.folio`, but not in `.tex`. Very large expressions and unusual page layouts should be checked in print preview before submission.

The API is for a trusted local workstation. Do not expose it publicly without authentication, HTTPS, deployment-specific origin restrictions, and stronger resource isolation.
