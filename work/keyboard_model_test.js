const assert = require('node:assert/strict');
const fs = require('node:fs');

const desktop = fs.readFileSync(new URL('../outputs/desktop.html', `file://${__filename}`), 'utf8');
const script = desktop.match(/<script id="folio-app">([\s\S]*?)<\/script>/)?.[1];
const mathJaxPath = new URL('../outputs/vendor/tex-svg.js', `file://${__filename}`);

assert.ok(script, 'desktop editor must contain its interaction script');
assert.doesNotThrow(() => new Function(script), 'desktop editor script must parse');
assert.ok(fs.statSync(mathJaxPath).size > 1_000_000, 'offline MathJax bundle must be present');

for (const feature of [
  'id="editor"', 'id="command-input"', 'id="export-button"', 'id="preview-button"',
  'id="preview-pane"', 'id="preview-body"', 'vendor/tex-svg.js',
  'id="help-dialog"', 'id="help-search"', 'id="export-dialog"', 'id="print-paper"',
  'id="meta-title"', 'id="meta-student"', 'id="meta-course"', 'id="meta-date"',
  "linalg: {", "calculus: {", "proof: {", "aliases: ['1'", "aliases: ['2'", "aliases: ['3'",
  'command.match(/^M', 'function handleNormalKey', 'function handleVisualKey',
  "key === 'i'", "key === 'v'", "key === 'd'", "key === 'y'", "key === 'p'",
  "pending === 'q'", "pending === '@'", 'function applyMathMacro',
  'localStorage.setItem', 'new Blob', 'link.download = safeFilename(extension)',
  'function openHelp', 'function filterHelp', "command.match(/^help", "command.match(/^set",
  'const assignmentTemplates', 'function applyAssignmentTemplate', "command.endsWith('!')", 'id="template-button"',
  'let documentText', 'function cycleMathMode', 'function renderPreview', 'function queueTypeset',
  'function previousContentLine', 'function repeatLastMatrix', 'function continueProofStep',
  'function buildInferenceRule', 'function transformPreviousLine', 'function wrapLastMatrix',
  'function buildContradiction', 'function expandSnippet', 'const commonSnippets', 'const modeSnippets',
  "key.toLowerCase() === 'm'", "command === 'preview'", 'function appendDocument',
  'function toMarkdown', 'function toLatex', 'function buildPrintPaper', 'window.print()',
  'data-export="md"', 'data-export="tex"', 'data-export="pdf"', 'data-export="txt"',
  'function resetBuffer()', "command === 'new'"
]) assert.ok(desktop.includes(feature), `missing desktop editor feature: ${feature}`);

assert.ok(!desktop.includes('let documents ='), 'math modes must share one document buffer');
assert.ok(!desktop.includes('class="contextbar"'), 'math modes must not be presented as document tabs');
assert.ok(desktop.includes("if (key === '\\\\') { leader = true;"), 'backslash must activate the math leader');
assert.ok(!desktop.includes("if (key === ' ') { leader = true;"), 'Space must remain available to the browser');
assert.ok(!desktop.includes('matrix scaffold'), 'math macros must operate on document context, not insert canned scaffolds');
assert.ok(!desktop.includes('assumption\', \'assume'), 'proof macros must operate on prior proof steps');
for (const mode of ['LINALG', 'CALC', 'PROOF']) assert.ok(desktop.includes(`label: '${mode}'`), `missing ${mode} context`);
for (const key of ['c', 'n', 't', 'b']) {
  const token = `['\\\\ ${key}'`;
  assert.ok(desktop.split(token).length - 1 >= 3, `\\\\ ${key} must exist in every math mode`);
}
assert.doesNotMatch(desktop, /data-device|ipad/i);
console.log('desktop editor contract passed');
