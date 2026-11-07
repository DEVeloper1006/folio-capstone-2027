'use strict';

// Persisted/generated modes are data. They never contain executable actions.
globalThis.FolioModes = {
  validate(mode) {
    const text = (value, max) => typeof value === 'string' && value.trim().length > 0 && value.length <= max && !/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/.test(value);
    if (!mode || !/^[a-z][a-z0-9-]{0,79}$/.test(mode.id) || ['linalg', 'calculus', 'proof', 'new', 'uncertain'].includes(mode.id) ||
        !text(mode.title, 48) || ['new', 'linalg', 'calc', 'proof'].includes(mode.title.trim().toLowerCase()) ||
        !text(mode.summary, 300) || !Array.isArray(mode.bindings) || mode.bindings.length < 3 || mode.bindings.length > 8) throw Error('Invalid math mode');
    const used = new Set();
    for (const binding of mode.bindings) {
      if (!/^[a-z]$/.test(binding.key) || used.has(binding.key) || !text(binding.label, 80) ||
          typeof binding.before !== 'string' || typeof binding.after !== 'string' || !text(binding.before + binding.after, 1200)) throw Error('Invalid or duplicate mode binding');
      used.add(binding.key);
      const source = binding.before + binding.after;
      if (/(?<!\\)\$/.test(source) || source.includes('{{cursor}}') || /\\(?:require|href|url|htmlClass|htmlId|htmlStyle|class|cssId|style|def|gdef|newcommand|renewcommand|let|includegraphics|input|include|write|openout|read)\b/.test(source)) throw Error('Unsupported mode notation');
    }
    return mode;
  },

  mathBody(template) {
    const source = template.trim();
    const delimiter = source.startsWith('$$') ? '$$' : '$';
    if (!source.startsWith(delimiter) || !source.endsWith(delimiter) || source.length <= delimiter.length * 2) throw Error('Templates must be complete $...$ or $$...$$ math');
    const body = source.slice(delimiter.length, -delimiter.length);
    if (/(?<!\\)\$/.test(body)) throw Error('Unbalanced math delimiters');
    return body;
  },

  equal(a, b) {
    return ['id', 'title', 'summary'].every(key => a[key] === b[key]) &&
      a.bindings.length === b.bindings.length && a.bindings.every((binding, index) =>
        ['key', 'label', 'before', 'after'].every(key => binding[key] === b.bindings[index][key]));
  },

  expand(binding, selection = '') {
    return { text: '$' + binding.before + selection + binding.after + '$', cursor: 1 + binding.before.length + selection.length };
  },

  passage(source, start, end) {
    if (start !== end) return source.slice(start, end);
    // The active Markdown section, not an unrelated domain elsewhere in the file.
    const headings = [...source.matchAll(/^#{1,3}\s+.*$/gm)];
    const before = headings.filter(heading => heading.index <= start).at(-1);
    const after = headings.find(heading => heading.index > start);
    const from = before?.index ?? 0;
    const to = after?.index ?? source.length;
    const section = source.slice(from, to).trim();
    if (section.length <= 4000) return section;
    // A bounded cursor neighborhood is explicit context, not a truncated whole document.
    return ((before?.[0] || '') + '\n' + source.slice(Math.max(from, start - 2000), Math.min(to, end + 2000))).trim();
  },

  blocks(source) {
    const blocks = [];
    let pending = [];
    let open = false;
    for (const line of source.split('\n')) {
      pending.push(line);
      const delimiters = [...line.matchAll(/(?<!\\)\$\$/g)].length;
      if (delimiters % 2) open = !open;
      if (!open) { blocks.push(pending.join('\n')); pending = []; }
    }
    if (pending.length) blocks.push(pending.join('\n'));
    return blocks;
  }
};
if (typeof module !== 'undefined') module.exports = globalThis.FolioModes;
