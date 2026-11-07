FOLIO DESKTOP — GROUP BUILD

RUN
1. Unzip the package.
2. Keep desktop.html, tokens.css, native.css, math-modes.js and vendor together.
3. Double-click desktop.html. Chrome, Safari, Firefox, or Edge will work.

No installation, account, internet connection, or local server is required.
Documents and assignment metadata are saved in that browser on that computer.
AI step translation and dynamic mode creation require the native Mac app
and a separately installed Ollama model. Saved custom modes work offline.

START
:help                 Open the complete command reference
:template             Load the editable Problem Set template
:M                    List math modes
:M linalg             Switch to Linear Algebra
:M calc               Switch to Calculus
:M proof              Switch to Proof mode
Ctrl-m                Cycle modes without changing the file
:modes / :bindings    Inspect the mode library and active notation keys
\ + mode key          Run the active math macro in Normal mode
i                     Enter Insert mode
Esc                   Return to Normal mode
:w                    Save locally
:export               Open assignment metadata and export options

EXPORTS
Markdown, LaTeX, plain text, and print-ready PDF are supported. For PDF,
choose Save as PDF in the browser's system print dialog.

LIVE LATEX
Use $...$ for inline math and $$...$$ for display math. Subscripts,
superscripts, fractions, roots, matrices, integrals, and standard TeX commands
compile in the document view. The renderer is included and works offline.

CONTEXT MACROS
The same four keys work in the three built-in modes: \ c copies the prior object, \ n
creates the next step, \ t transforms it, and \ b builds a larger structure.
Linear Algebra maps these to matrix copy, row reduction, RREF, and determinant.
Calculus maps them to expression copy, continuation, derivative, and integral.
Proof maps them to step copy, justification, inference rule, and contradiction.
Generated modes have their own labeled keys. Inspect :bindings before use.

TAB EXPANSIONS
In Insert mode, type a token and press Tab. Common: fr, sq, sum, prod, cases.
Linear Algebra: m2, m3, aug. Calculus: int, dint, lim, der.
Proof: imp, iff, contra. Use :help snippets for the complete list.

IMPORTANT
Browser storage is local to the computer and browser being used. Export work
before clearing browser data or moving to another computer.
