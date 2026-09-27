# Refactor Notes: InkPad → Folio iPad Interface

## Existing Code Audit

### KEEP (reuse with modifications)
- `InkCore/StrokeProvider.swift` — protocol + PKStrokeProvider. Clean, reusable as-is.
- `InkCore/CanvasViewModel.swift` — @Observable, autosave, drawingChanged. Needs extensions for tool state, session mode, math mode.
- `InkCore/PageBackground.swift` — PageBackgroundStyle enum + PageBackgroundView. Needs dot-grid added, warm paper color.
- `InkCore/ExportService.swift` — PNG/PDF render. Needs LaTeX/Markdown mock export added.
- `App/Models/Notebook.swift` — SwiftData model. Needs modeBadge, coverColor, lastEditedAt fields.
- `App/Models/Page.swift` — SwiftData model. Needs mathMode, step/branch relationships.
- `App/Navigation/AppNavigation.swift` — NavigationStack. Keep structure, adjust destinations.
- `inkpadApp.swift` — Entry point. Needs Step/Branch models added to schema, seed data on first launch.

### REFACTOR (significant changes needed)
- `InkCore/CanvasView.swift` — **Must remove PKToolPicker**. Replace with custom tool driving (PKInkingTool, PKEraserTool, PKLassoTool set programmatically). Add drawingPolicy toggle, pencil double-tap/squeeze handling.
- `App/Views/LibraryView.swift` — Needs Goodnotes-style grid with colored covers, mode badge, "New notebook" tile, duplicate action, long-press context menu.
- `App/Views/NotebookView.swift` — Currently a page list. Needs to become the full notebook canvas screen with toolbar, session control, gutter, ghost typeset, annotations, branches drawer, chat panel, voice pill.
- `App/Views/CanvasPageView.swift` — Currently hosts canvas + toolbar. Most of this becomes NotebookView. ShareSheet can be reused for export.

### DELETE
- PKToolPicker usage in CanvasView.swift (lines 15-20, coordinator toolPicker property)

### NEW FILES NEEDED

#### Theme
- `FolioTheme.swift` — All colors, fonts, spacing tokens

#### InkCore additions
- (None — keep InkCore minimal per architecture spec)

#### Overlay
- `Overlay/AnnotationLayer.swift` — AI annotations in teal handwriting
- `Overlay/StepGutterView.swift` — Left-margin status badges
- `Overlay/SelectionHullView.swift` — Teal dashed lasso hull
- `Overlay/RadialMenuView.swift` — Pill-button radial menu

#### Services
- `Services/MathEngine.swift` — Protocol + MockMathEngine
- `Services/RecognitionService.swift` — Protocol + MockRecognitionService
- `Services/AssistantService.swift` — Protocol + MockAssistantService + LayaAssistantService (empty) + JevAssistantService (empty)
- `Services/BranchStore.swift` — Protocol + MockBranchStore

#### App/Models
- `App/Models/Step.swift` — SwiftData model for detected math steps
- `App/Models/Branch.swift` — SwiftData model for solution forks

#### App/Views
- `App/Views/ToolStripView.swift` — Goodnotes-style floating toolbar
- `App/Views/SessionModeControl.swift` — Solo/Coach/Check segmented control
- `App/Views/GhostTypesetView.swift` — Serif italic LaTeX ghost under handwriting
- `App/Views/BranchesDrawer.swift` — Right-edge BRANCHES tab + drawer
- `App/Views/VoicePillView.swift` — Mic FAB + floating voice pill
- `App/Views/ChatPanelView.swift` — Side panel text chat
- `App/Views/TypesetPaneView.swift` — WKWebView with MathJax for typeset math
- `App/Views/CommandPaletteView.swift` — ⌘K fuzzy search palette
- `App/Views/ExportSheetView.swift` — PNG/PDF/LaTeX/Markdown export with metadata
- `App/Views/HelpSheetView.swift` — Gestures, shortcuts, macros reference
- `App/Views/MacroTrayView.swift` — Collapsible macro slots
- `App/Views/StatusChipView.swift` — Floating footer with mode/save/step count

#### Resources
- `Resources/Caveat-Regular.ttf` + `OFL.txt` — Handwriting font
- `Resources/tex-svg.js` + `mathjax.html` — Bundled MathJax for offline typeset
- `Info.plist` — Mic usage description

## Build Order (from CLAUDE.md)
1. Theme tokens
2. Library (Goodnotes-style grid)
3. Canvas + custom tool strip (remove PKToolPicker)
4. Step gutter + ghost typeset
5. Solo/Coach/Check + AI annotations
6. Lasso radial menu
7. Branches drawer
8. Voice pill + chat panel
9. Typeset pane (WKWebView + MathJax)
10. Command palette, export, help
11. Mock data polish (recreate ipad-mockup.png)
