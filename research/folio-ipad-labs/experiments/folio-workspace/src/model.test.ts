import { describe, expect, it, vi, beforeEach } from 'vitest';
import {
  block,
  initialWorkspace,
  latexDocument,
  loadWorkspace,
  newDocument,
  parseImport,
  validateDocument,
} from './model';

beforeEach(() => {
  vi.stubGlobal('localStorage', { getItem: vi.fn(() => null), setItem: vi.fn() });
});

describe('document format', () => {
  it('round trips all supported block types without mutating the original', () => {
    const doc = newDocument();
    doc.blocks = [
      block('heading', 'Title'),
      block('text', 'Reasoning'),
      block('math', 'x^2'),
      {
        ...block('ink'),
        strokes: [
          {
            id: 'stroke-1',
            color: '#274a73',
            width: 2.5,
            points: [{ x: 10, y: 20, pressure: 0.5 }],
          },
        ],
      },
    ];
    const imported = parseImport(JSON.stringify({ version: 1, document: doc }));
    expect(imported.id).not.toBe(doc.id);
    expect(imported.blocks.map((b) => [b.type, b.content, b.strokes])).toEqual(
      doc.blocks.map((b) => [b.type, b.content, b.strokes]),
    );
    expect(imported.blocks[0].id).not.toBe(doc.blocks[0].id);
    imported.blocks[3].strokes![0].points[0].x = 999;
    expect(doc.blocks[3].strokes![0].points[0].x).toBe(10);
  });
  it('preserves export exclusions', () => {
    const doc = newDocument();
    doc.blocks[0].included = false;
    expect(parseImport(JSON.stringify({ version: 1, document: doc })).blocks[0].included).toBe(
      false,
    );
  });
  it('rejects unsupported versions', () =>
    expect(() => parseImport(JSON.stringify({ version: 2, document: newDocument() }))).toThrow(
      'Unsupported',
    ));
  it('rejects malformed JSON', () => expect(() => parseImport('{')).toThrow('valid JSON'));
  it('rejects duplicate step ids', () => {
    const d = newDocument();
    d.blocks.push(d.blocks[0]);
    expect(() => validateDocument(d)).toThrow('invalid step');
  });
  it('rejects unbounded stroke coordinates', () => {
    const d = newDocument();
    d.blocks = [
      {
        ...block('ink'),
        strokes: [
          { id: 's', color: '#274a73', width: 2, points: [{ x: Infinity, y: 0, pressure: 1 }] },
        ],
      },
    ];
    expect(() => validateDocument(d)).toThrow('coordinates');
  });
  it('rejects non-color stroke data', () => {
    const d = newDocument();
    d.blocks = [
      { ...block('ink'), strokes: [{ id: 's', color: 'url(evil)', width: 2, points: [] }] },
    ];
    expect(() => validateDocument(d)).toThrow('stroke');
  });
  it('provides useful starting documents', () => {
    const w = initialWorkspace();
    expect(w.documents).toHaveLength(3);
    for (const d of w.documents) expect(validateDocument(d)).toEqual(d);
  });
});

describe('local persistence', () => {
  it('starts fresh without saved data', () =>
    expect(loadWorkspace().workspace.documents.length).toBe(3));
  it('restores active document and every step', () => {
    const w = initialWorkspace();
    w.activeId = w.documents[1].id;
    vi.mocked(localStorage.getItem).mockReturnValue(JSON.stringify(w));
    expect(loadWorkspace().workspace).toEqual(w);
  });
  it('does not overwrite corrupt data', () => {
    vi.mocked(localStorage.getItem).mockReturnValue('{bad');
    expect(loadWorkspace().warning).toContain('not been overwritten');
    expect(localStorage.setItem).not.toHaveBeenCalled();
  });
  it('recovers a stale active id', () => {
    const w = initialWorkspace();
    w.activeId = 'gone';
    vi.mocked(localStorage.getItem).mockReturnValue(JSON.stringify(w));
    expect(loadWorkspace().workspace.activeId).toBe(w.documents[0].id);
  });
});

describe('LaTeX export', () => {
  it('escapes plain text, includes math, omits scratch work', () => {
    const doc = newDocument();
    doc.title = 'Test & 10%';
    doc.blocks = [
      block('text', 'x_y & #1'),
      block('math', 'x^2'),
      { ...block('text', 'secret scratch'), included: false },
      block('ink'),
    ];
    const latex = latexDocument(doc);
    expect(latex).toContain('Test \\& 10\\%');
    expect(latex).toContain('x\\_y \\& \\#1');
    expect(latex).toContain('x^2');
    expect(latex).not.toContain('secret scratch');
    expect(latex).toContain('Handwriting omitted');
  });
});
