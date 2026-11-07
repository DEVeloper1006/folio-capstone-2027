const assert = require('node:assert/strict');
const modes = require('../outputs/math-modes.js');

// Pure data boundaries; no model responses are substituted in live checks.
const result = modes.expand({before: '\\lvert ', after: '\\rangle'}, 'a{{cursor}}');
assert.equal(result.text, '$\\lvert a{{cursor}}\\rangle$');
assert.equal(result.cursor, '$\\lvert a{{cursor}}'.length);
assert.equal(modes.expand({before: '|', after: '|'}).text, '$||$');
assert.throws(() => modes.mathBody('$x$$'));
assert.throws(() => modes.mathBody('x'));
assert.equal(modes.mathBody('$$x$$'), 'x');

const source = '# First\n$x$\n\n# Second\n$y$\n';
assert.equal(modes.passage(source, source.indexOf('$y$'), source.indexOf('$y$')), '# Second\n$y$');
assert.equal(modes.passage(source, 8, 11), '$x$');
assert.equal(modes.passage('', 0, 0), '');
assert.ok(modes.passage('x'.repeat(100000), 50000, 50000).length <= 4001);
assert.deepEqual(modes.blocks('before\n$$\nx^2\n$$\nafter'), ['before', '$$\nx^2\n$$', 'after']);
assert.deepEqual(modes.blocks('$$x$$\n$y$'), ['$$x$$', '$y$']);
assert.deepEqual(modes.blocks('$$\nx'), ['$$\nx']);

const mode = { id: 'test-mode', title: 'Test notation', summary: 'Validates the data contract.', bindings: ['a', 'b', 'c'].map(key => ({ key, label: key, before: 'x_{', after: '}' })) };
assert.equal(modes.validate(mode), mode);
const reordered = { bindings: mode.bindings.map(({key, label, before, after}) => ({after, before, label, key})), summary: mode.summary, title: mode.title, id: mode.id };
assert.ok(modes.equal(mode, reordered));
assert.ok(!modes.equal(mode, {...reordered, title: 'Changed'}));
assert.ok(!modes.equal(mode, {...reordered, bindings: [...reordered.bindings].reverse()}));
for (const invalid of [
  { ...mode, id: 'proof' },
  { ...mode, id: 'new' },
  { ...mode, title: ' NEW ' },
  { ...mode, id: '__proto__' },
  { ...mode, bindings: [mode.bindings[0], mode.bindings[0], mode.bindings[2]] },
  { ...mode, bindings: mode.bindings.map(binding => ({ ...binding, before: '\\href{https://example.com}{' })) },
  { ...mode, bindings: mode.bindings.map(binding => ({ ...binding, before: '\frac{' })) },
  { ...mode, bindings: mode.bindings.map(binding => ({ ...binding, before: '$x' })) }
]) assert.throws(() => modes.validate(invalid));
console.log('Mode data, placeholders, active-section context, and multiline block checks passed');
