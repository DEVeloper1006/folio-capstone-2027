FOLIO

Product scope
  Folio supports the student's reasoning; it is not an automatic solver.
  It translates a step the student has chosen, asks for clarification when
  needed, and offers conceptual hints without completing the solution.
  The student reviews and accepts every proposed document edit.
  Adaptive modes change the notation toolbox, not the student's mathematics.
  The installed pretrained models are development placeholders. Model training
  and model-quality work are deferred to your own model; the editor uses the
  selected Ollama model through the existing request/response contract.

Verification status
  The native save/reopen, step proposal/accept/undo, and Command-S paths have
  been exercised in the visible Mac app. Offline regression checks pass.
  Adaptive mode generation is still under validation: the installed models
  have not passed the complete quaternion, qubit, and complex-analysis flow.
  These failures remain documented model-integration limitations, not a reason
  to keep tuning pretrained models. The editor's acceptance, persistence, and
  invalid-output handling still need independent verification. Invalid modes
  are rejected rather than replaced with canned notation.

Mac app
  Build: bash macos/build.sh
  Run:   open build/Folio.app
  Check without AI: bash macos/check.sh
  Full live checks (requires the named model in Ollama):
    bash macos/check.sh qwen3.5:9b
  This is the current candidate's regression command, not a passing-model
  recommendation. The full live check currently exposes generation failures.
  Checks use isolated web storage and never replace your saved workspace.
  Building requires Xcode Command Line Tools; the JS checks also use Node.js.

The app bundles the existing editor and offline MathJax inside a native
AppKit/WebKit window. It runs without the browser server. The current build
targets Apple Silicon Macs, macOS 13 or later, and is locally ad-hoc signed.

Browser preview
  python3 -m http.server 8765 --bind 127.0.0.1 --directory outputs
  http://127.0.0.1:8765/desktop.html

Editing
  i / Escape         Insert / Normal mode
  :help              All existing Vim commands, macros, snippets and exports
  :modes             Mode library, automatic detection, local model selection
  :bindings          Inspect the active mode's notation keys
  :M name            Select and pin any saved mode
  :auto on           Follow the active mathematical section automatically
  :detect            Detect the subject now (also Cmd-Shift-D)
  :mode create topic Generate a new notation toolbox for a named subject
  :preview           Toggle the rendered LaTeX
  :step instruction  Review a proposed notation for your chosen next step
  :hint question     Ask for guidance without document edits

The Mac window starts with just the source editor and status line. File,
View, Math and Help menus expose the other controls. macOS Dictation can
be used in the assistant's text field; voice testing was skipped at your request.

Storage
  Autosave: ~/Library/Application Support/Folio/workspace.folio
  File > Save As saves a separate .folio document including modes, registers
  and assignment metadata. Open accepts .folio and UTF-8 text, including TeX.
  Export provides Markdown, LaTeX and text through native save panels.
  Print/PDF uses the native print dialog.

The Mac app has separate storage from your browser. Export existing browser
text and open that file in the Mac app to bring it over. The original browser
storage is not modified. Never clear browser data before exporting work.

Learning assistant
  Connects only to the local Ollama service at 127.0.0.1:11434.
  The model list comes from that service; model weights are not bundled in
  Folio.app. The current test candidate is qwen3.5:9b, installed in Ollama.
  No model has yet passed every adaptive-mode check in this project.
  Ollama must be running before opening the assistant.
  A step includes an explanation and a proposed mode. Acceptance appends the
  step at the captured line. It refuses to apply against changed text or mode.
  Hints and clarification questions do not edit the document.
  Generated mathematics is not formally verified. Review every proposal;
  the assistant can misunderstand a rule or produce incorrect mathematics.
  Requests stay on this Mac and use no cloud AI account.

Adaptive notation
  Built-in toolboxes cover linear algebra, calculus, and propositional logic.
  The model identifies the subject from your selection, or the Markdown
  section containing the cursor, then matches it against the saved library.
  A new subject generates labeled backslash-leader keys. There is no fixed
  quaternion/qubit lookup table. Every key is declarative LaTeX, not code.
  Generated modes are checked for valid data and renderable TeX before they
  are installed. Their mathematical meaning still needs your review.
  Automatic detection waits for a pause in Normal mode. It never changes
  the source text. Editing or moving to another section cancels stale work.
  Choosing a mode manually pins it and turns automatic detection off.
  Installed modes remain usable without Ollama. Mode creation and the step
  assistant require the native Mac app; the browser does not call Ollama.

Demo
  Open demo/Adaptive math.txt through File > Open.
  Open :modes, choose your installed model, then enable automatic detection.
  Move the cursor into Quaternion rotations and return to Normal mode.
  Wait for creation, inspect :bindings, close the dialog, and press backslash
  followed by a displayed key. Type an argument; Escape then u undoes it.
  Move to Qubits, then Complex analysis: watch the toolbox change without
  changing the notebook. Return to an earlier section to reuse its mode.
  Pin a mode with :M name to stop automatic switching.
  Use :step to request one operation, inspect the preview, accept, then undo.
  Save As .folio and reopen it to retain your custom modes and preferences.

Safety and limits
  AI output can be mathematically wrong even when it renders. This is a
  notation assistant, not a proof checker or computer algebra system.
  Invalid responses are reported; no canned answers or silent repairs are
  substituted. Retry is manual. Detection speed depends on local hardware.
  Save As is a separate snapshot; autosave remains the recovery workspace.
  Corrupt recovery data is preserved before an empty workspace is started.
  The native workspace limit is 4 MB and 64 generated modes.
  Local ad-hoc signing is not notarization for public distribution.

Integration deferred
  outputs/ipad.html is the original visual prototype, not handwriting
  recognition or a working companion. Real-time iPad integration requires
  the existing iPad app source/protocol. This Mac build does not sync yet;
  iPad integration is deferred at your request.

Source layout
  outputs/desktop.html  Shared browser/Mac editing engine
  outputs/native.css    Minimal Mac layout and assistant UI
  macos/Folio.swift     Native lifecycle, menus, persistence and file bridge
  macos/Assistant.swift Local model requests and response validation
  macos/MathMode.swift  Declarative mode and recognition contracts
  macos/Workspace.swift Validated storage and recovery
  outputs/math-modes.js Shared mode validation and document helpers
  macos/build.sh        Reproducible local .app build
  macos/check.sh        Offline checks plus optional real-model checks

API references
  https://developer.apple.com/documentation/webkit/wkwebview
  https://docs.ollama.com/api/chat
