export type Point = { x: number; y: number; pressure: number };
export type Stroke = { id: string; points: Point[]; color: string; width: number };
export type Block = {
  id: string;
  type: 'math' | 'text' | 'heading' | 'ink';
  content: string;
  included: boolean;
  note?: string;
  strokes?: Stroke[];
};
export type FolioDocument = {
  id: string;
  title: string;
  subject: string;
  updatedAt: string;
  blocks: Block[];
};
export type Workspace = { version: 1; documents: FolioDocument[]; activeId: string };
export const STORAGE_KEY = 'folio.workspace.v1';
export const uid = () => crypto.randomUUID();
export const block = (type: Block['type'], content = '', note?: string): Block => ({
  id: uid(),
  type,
  content,
  included: true,
  ...(note ? { note } : {}),
  ...(type === 'ink' ? { strokes: [] } : {}),
});
export function newDocument(): FolioDocument {
  return {
    id: uid(),
    title: 'Untitled document',
    subject: 'Mathematics',
    updatedAt: new Date().toISOString(),
    blocks: [block('math')],
  };
}
export function initialWorkspace(): Workspace {
  const linear: FolioDocument = {
    id: uid(),
    title: 'Systems of linear equations',
    subject: 'Linear algebra',
    updatedAt: new Date().toISOString(),
    blocks: [
      block('heading', '01  /  Finding a unique solution'),
      block(
        'text',
        'Solve the system by reducing its augmented matrix. Keep each step of your reasoning together, from the first idea to the final answer.',
      ),
      block(
        'math',
        String.raw`\begin{cases}x + 2y - z = 3\\2x + y + z = 6\\-x + y + 2z = 1\end{cases}`,
      ),
      block(
        'text',
        'Write the coefficients as an augmented matrix, then find its reduced row echelon form.',
      ),
      block(
        'math',
        String.raw`\begin{bmatrix}1 & 2 & -1 & 3\\2 & 1 & 1 & 6\\-1 & 1 & 2 & 1\end{bmatrix}`,
        'Augmented matrix',
      ),
      block(
        'text',
        'Select the matrix above and choose /rref in the command panel. The result will be added as a new, editable step.',
      ),
    ],
  };
  const calculus: FolioDocument = {
    id: uid(),
    title: 'A little calculus',
    subject: 'Calculus',
    updatedAt: new Date().toISOString(),
    blocks: [
      block('heading', 'The product rule, in practice'),
      block(
        'text',
        'Differentiate the expression below with respect to x. Select it, then run /derivative. Your original expression stays exactly where it is.',
      ),
      block('math', String.raw`x^2\sin\left(x\right)`),
      block('heading', 'An antiderivative'),
      block(
        'text',
        'Select the next expression and run /integral. The result includes an arbitrary constant of integration.',
      ),
      block('math', String.raw`3x^2+2x+1`),
    ],
  };
  const blank: FolioDocument = {
    id: uid(),
    title: 'Room to think',
    subject: 'Scratch work',
    updatedAt: new Date().toISOString(),
    blocks: [
      block(
        'text',
        'A place for the ideas that are not quite ready yet. Use a pen, your keyboard, or a little of both.',
      ),
      block('ink'),
    ],
  };
  return { version: 1, documents: [linear, calculus, blank], activeId: linear.id };
}
const object = (x: unknown): x is Record<string, unknown> =>
  typeof x === 'object' && x !== null && !Array.isArray(x);
const text = (x: unknown, max = 20000): x is string => typeof x === 'string' && x.length <= max;
export function validateDocument(value: unknown): FolioDocument {
  if (
    !object(value) ||
    !text(value.id, 100) ||
    !text(value.title, 200) ||
    !text(value.subject, 100) ||
    !text(value.updatedAt, 100) ||
    !Array.isArray(value.blocks) ||
    value.blocks.length > 500
  )
    throw new Error('This is not a supported Folio document.');
  const seen = new Set<string>();
  for (const b of value.blocks) {
    if (
      !object(b) ||
      !text(b.id, 100) ||
      seen.has(b.id) ||
      !['math', 'text', 'heading', 'ink'].includes(String(b.type)) ||
      !text(b.content) ||
      typeof b.included !== 'boolean' ||
      (b.note !== undefined && !text(b.note, 2000))
    )
      throw new Error('The document contains an invalid step.');
    seen.add(b.id);
    if (b.type === 'ink') {
      if (!Array.isArray(b.strokes) || b.strokes.length > 2000)
        throw new Error('Invalid handwriting data.');
      let count = 0;
      const strokeIds = new Set<string>();
      for (const stroke of b.strokes) {
        if (
          !object(stroke) ||
          !text(stroke.id, 100) ||
          strokeIds.has(stroke.id) ||
          !text(stroke.color, 20) ||
          !/^#[a-fA-F0-9]{6}$/.test(stroke.color) ||
          typeof stroke.width !== 'number' ||
          stroke.width < 0.5 ||
          stroke.width > 20 ||
          !Array.isArray(stroke.points) ||
          stroke.points.length > 20000
        )
          throw new Error('Invalid handwriting stroke.');
        strokeIds.add(stroke.id);
        count += stroke.points.length;
        if (count > 100000) throw new Error('The handwriting is too large to import.');
        for (const p of stroke.points)
          if (
            !object(p) ||
            ![p.x, p.y, p.pressure].every(
              (n) => typeof n === 'number' && Number.isFinite(n) && Math.abs(n) <= 10000,
            )
          )
            throw new Error('Invalid handwriting coordinates.');
      }
    }
  }
  return structuredClone(value) as FolioDocument;
}
export function parseImport(raw: string): FolioDocument {
  if (raw.length > 5_000_000) throw new Error('Documents must be smaller than 5 MB.');
  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error('This file is not valid JSON. Choose a .folio file.');
  }
  if (!object(value) || value.version !== 1 || !value.document)
    throw new Error('Unsupported file version. Choose a Folio v1 document.');
  const doc = validateDocument(value.document);
  return {
    ...doc,
    id: uid(),
    blocks: doc.blocks.map((b) => ({ ...b, id: uid() })),
    updatedAt: new Date().toISOString(),
  };
}
export function loadWorkspace(): { workspace: Workspace; warning?: string } {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { workspace: initialWorkspace() };
    const value = JSON.parse(raw);
    if (
      value.version !== 1 ||
      !Array.isArray(value.documents) ||
      !value.documents.length ||
      value.documents.length > 100
    )
      throw new Error();
    const documents = value.documents.map(validateDocument);
    if (new Set(documents.map((d: FolioDocument) => d.id)).size !== documents.length)
      throw new Error();
    return {
      workspace: {
        version: 1,
        documents,
        activeId: documents.some((d: FolioDocument) => d.id === value.activeId)
          ? value.activeId
          : documents[0].id,
      },
    };
  } catch {
    return {
      workspace: initialWorkspace(),
      warning:
        'Saved data could not be opened. It has not been overwritten. Download a backup before resetting storage.',
    };
  }
}
export const fileName = (title: string) =>
  title.replace(/[^a-zA-Z0-9 _-]/g, '').trim() || 'Folio document';
export function download(content: string, filename: string, type: string) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export function latexDocument(doc: FolioDocument) {
  const escape = (s: string) =>
    s.replace(
      /[\\{}%$&#_^~]/g,
      (c) =>
        ({ '\\': '\\textbackslash{}', '~': '\\textasciitilde{}', '^': '\\textasciicircum{}' })[c] ||
        '\\' + c,
    );
  return (
    `\\documentclass[11pt]{article}\n\\usepackage{amsmath,amssymb}\n\\usepackage[margin=1in]{geometry}\n\\title{${escape(doc.title)}}\n\\date{}\n\\begin{document}\n\\maketitle\n` +
    doc.blocks
      .filter((b) => b.included)
      .map((b) =>
        b.type === 'math'
          ? `\\[\n${b.content}\n\\]${b.note ? `\n\\noindent\\textit{${escape(b.note)}}\n` : ''}`
          : b.type === 'heading'
            ? `\\section*{${escape(b.content)}}`
            : b.type === 'ink'
              ? '% Handwriting omitted from LaTeX. Use PDF or .folio to preserve ink.'
              : escape(b.content) + '\n',
      )
      .join('\n\n') +
    '\n\\end{document}\n'
  );
}
