# InkPad → Folio iPad Interface (UI only)

## Context
InkPad is the iPad prototype of Folio, an AI-assisted math workspace (capstone).
On iPad, Folio should feel like **Goodnotes / Notability first**, a familiar
handwriting notebook, with Folio's math-aware layer added on top of it.

Design references are in `/design/`:
- `ipad-mockup.png` is the **primary visual target**: the canvas, step
  badges, AI ink annotations, radial menu, and branches tab.
- `desktop.html`, `tokens.css`, and `desktop-mockup.png` are the teammate's
  desktop mockup. Borrow its **features** (math modes, macros, command
  palette, typeset view, export, help, status info), not its terminal look.

**Scope: interface only.** No ML, OCR, CAS, voice models, or network. Every
"smart" surface runs on mock data behind a protocol, so real engines can
drop in later.

The Xcode project already exists (SwiftUI, iPadOS 18+). Do NOT regenerate the
.xcodeproj. Add or edit Swift files, and tell me about any Xcode settings needed.

## Visual language (from ipad-mockup.png)
- **Paper:** warm off-white (`#F4F2EC`-ish) with a subtle **dot grid**.
  The page backgrounds are dot, grid, lined, and blank.
- **Ink:** near-black graphite (`#1C1C1A`).
- **Accent:** muted teal (`#4E9A95`-ish). Use it ONLY for AI-authored
  content: annotations, arrows, selection fills, the accept chip.
- **Status colors:** green = verified, amber = unchecked/warning,
  red = error. Keep them muted. Each has an outlined circle in normal state
  and a filled tint in the error state.
- **Chrome:** light, rounded, and floating, like Goodnotes. Use white
  pill/capsule buttons with soft shadows and a grey segmented control.
- **Type:**
  - UI uses SF Pro (system).
  - Ghost typeset lines use a serif italic (New York / Georgia).
  - AI annotations use a handwriting-style font. Ship one open-source
    handwriting font (e.g. Caveat, OFL) and include its license file.
- Put every color and font into `FolioTheme.swift` as tokens. Port the
  neutral names from `/design/tokens.css` where they overlap.
- Light mode only for now.

## Screens

### 1. Library (Goodnotes-style)
- A grid of notebook covers (title, last edited, mode badge), plus a "New
  notebook" tile.
- Covers use flat, paper-toned colors.
- Long-press gives rename, duplicate, and delete.

### 2. Notebook canvas (main screen)

**Top toolbar.** Goodnotes-like, floating, and compact:
- Left side: back to Library, notebook title, page-thumbnail sidebar toggle.
- Center: the tool strip, in this order:
  - pen, highlighter, eraser, lasso
  - 3 ink swatches, graphite/blue/red, plus a width picker
  - undo, redo
- Right side: math mode chip (`LINALG` / `CALC` / `PROOF`), typeset toggle,
  export, and a `⌘K` command palette button.

**Session mode control.** A segmented control reading `Solo | Coach | Check`,
floating top-center as in the mockup. It controls how much AI appears:
- `Solo` shows no annotations and no badges.
- `Coach` shows badges and Socratic hints.
- `Check` shows badges only, with no hints.

**Canvas.** PencilKit on the dotted paper, with vertical scrolling pages.

**Step gutter** (left margin):
- Each detected step gets a status badge: ✓ / ! / × (mock).
- Tapping a badge opens a small popover with a mock explanation.

**Ghost typeset:**
- Under each handwritten line, show the recognized LaTeX. It is rendered
  small, in serif italic, at ~40% opacity, as in the mockup.
- A per-page toggle hides it.

**AI annotations (Coach mode):**
- Written in teal handwriting font, e.g. "What's row 2's first entry now?".
- A hand-drawn-style curved arrow points to the target stroke.
- A `✓ tap to accept` chip sits next to it.
- A red squiggle underline marks the error location.
- Annotations live on a separate overlay layer and are never baked into the
  PKDrawing.

**Lasso → radial menu:**
- Lassoing strokes shows a teal dashed selection hull.
- Tapping the selection opens a radial menu of pill buttons:
  `Check · Hint · Explain · Formalize · Branch · Visualize`.
- Each action is mocked:
  - Check sets a badge.
  - Hint and Explain add an annotation.
  - Formalize opens the typeset pane.
  - Branch creates a branch.
  - Visualize opens a placeholder graph card.

**Branches tab:**
- A vertical `BRANCHES` tab on the right edge.
- Pulling it open shows a drawer with a tree of solution forks from this
  page. Each fork has a thumbnail and a status.
- Tapping a fork switches the canvas to it (mock).

**Bottom-right floating buttons** (stacked circular FABs):
1. **Voice assistant (placeholder).** See the section below.
2. **Chat.** Opens a side panel for a text conversation about the current
   page, with mock replies.

### 3. Typeset pane (from desktop mockup "compiled document")
- Opens as a right split view in landscape and a bottom sheet in portrait.
- It shows the page's steps as clean typeset math. Render the LaTeX with
  bundled MathJax (`/design/tex-svg.js` + `LICENSE-MathJax.txt`) in a
  `WKWebView`, fully offline.
- `LaTeX` / `Markdown` copy buttons in the header.

## Voice assistant (placeholder)
- A mic FAB above the chat FAB.
- Tapping it shows a floating **voice pill** near the bottom-center with:
  - an animated waveform (fake levels)
  - a live transcript line (mock text)
  - a model label, `Laya · on-device` or `Jev`, switchable in the pill's menu
  - a stop button
- States: idle → listening → thinking → responding. Responding writes a
  teal annotation onto the canvas.
- Pencil-hold + voice combo, placeholder only: while listening, lassoed
  content is shown as attached context ("talking about: selection").
- Build it behind an `AssistantService` protocol with a
  `MockAssistantService` that plays a scripted exchange. Leave
  `LayaAssistantService` and `JevAssistantService` as empty conforming
  types with a clear `// not implemented` and no fake behavior.
- Add the mic usage description to Info.plist now, but do NOT start real
  audio capture yet.

## Features borrowed from the desktop mockup
- **Math modes.** `LINALG` / `CALC` / `PROOF`. The mode chip and `Ctrl-M`
  on a hardware keyboard cycle through them.
- **Macros.** The same four slots in every mode, shown as a small
  collapsible "Macros" tray in the toolbar overflow. Each also has a
  hardware-keyboard shortcut.

| key | LINALG | CALC | PROOF |
|---|---|---|---|
| `\ c` | copy matrix | copy expression | copy prior step |
| `\ n` | row reduction | continue step | continue with justification |
| `\ t` | RREF | derivative | transform by inference |
| `\ b` | determinant | integral | build contradiction |

  Each macro appends a mock step, rendered as typeset ghost text plus a badge.

- **Command palette.** Opened with `⌘K` or `:` on a keyboard, or with Pencil
  squeeze. Commands: save, switch mode, load template, export, new page,
  help, toggle typeset, start voice. Fuzzy search.
- **Export sheet.** PNG, PDF, LaTeX (mock), Markdown (mock), plus assignment
  metadata fields (name, course, due date), as in the desktop export dialog.
- **Help sheet.** Gestures, Pencil shortcuts, keyboard shortcuts, and macros.
- **Status info.** A small floating footer chip (auto-hides) showing mode,
  save state, and step count. This is a light version of the desktop status
  line.

## Architecture
- **`/InkCore`.** Canvas wrapper, page backgrounds, serialization, and
  `StrokeProvider` (points with location, force, timestamp). No app-UI
  dependencies, so it can be reused in Folio.
- **`/Overlay`.** Annotation layer, step gutter, selection hull, radial menu.
  These are separate views positioned in canvas coordinates. They must stay
  aligned during zoom and scroll.
- **`/Services`.** Protocols plus mocks for `MathEngine`,
  `RecognitionService`, `AssistantService`, and `BranchStore`.
- **`/App`.** Library, notebook screen, sheets, and SwiftData models:
  Notebook → Page → Step, and Branch.
- Do not show `PKToolPicker`. Use the custom Goodnotes-style tool strip and
  drive `PKInkingTool`, `PKEraserTool`, and `PKLassoTool` directly.
- `drawingPolicy = .pencilOnly`, with a toggle. Fingers pan and zoom.
- Pencil double-tap switches pen ↔ eraser. Squeeze opens the palette.

## Mock data
- Seed a "Problem Set 1" notebook with 3 pages, one per math mode.
- Page 1 must recreate `ipad-mockup.png`:
  - the augmented 3×3 matrix and its row ops
  - ✓ / ! / × badges
  - the red squiggle
  - the teal hint "What's row 2's first entry now?" with its arrow and
    accept chip
  - one branch in the drawer
- Use seeded PencilKit strokes, or pre-rendered stroke paths if generating
  handwriting is impractical. Tell me which you choose.

## Out of scope
Real handwriting recognition, CAS, LLM/voice models, sync/collab, and PDF
import.

## How to work
1. First give me a short plan: file tree and build order. Wait for my OK.
2. Build in small steps, and make sure each step compiles. After each one,
   tell me exactly what to check on the iPad, in landscape and portrait.
3. Suggested build order:
   1. theme
   2. library
   3. canvas + tool strip
   4. gutter + ghost typeset
   5. Solo/Coach/Check + annotations
   6. lasso radial menu
   7. branches drawer
   8. voice pill + chat panel
   9. typeset pane
   10. palette, export, help
   11. mock data polish
4. Keep files small and focused. Don't present TODO stubs as working
   features.
5. Flag PencilKit, overlay-alignment, or WKWebView limitations instead of
   silently working around them.