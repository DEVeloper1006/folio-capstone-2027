/**
 * Define the notebook's supported cell types. Contains stable UUID identity, separate source fields for editable mathematics and Markdown prose, and creation of a new cell identifier.
 *
 * @file
 */

/** Keep a cell's stable identifier independent of the editor used to display it. */
interface CellIdentity {
  cellId: string
}

/** Create a new cell identifier. Sample pages use fixed identifiers so server and browser renders match. */
export function createCellId() {
  return crypto.randomUUID()
}

/** Store editable LaTeX in a mathematical cell backed by MathLive. */
export interface MathNotebookCell extends CellIdentity {
  kind: 'math'
  latex: string
}

/** Store Markdown source independently of whether the cell is being edited or rendered. */
export interface MarkdownNotebookCell extends CellIdentity {
  kind: 'markdown'
  markdown: string
}

/** Select an editor by cell kind while retaining the original source for each supported content format. */
export type NotebookCell = MathNotebookCell | MarkdownNotebookCell

/** Remove a single enclosing Markdown or TeX math delimiter pair from clipboard text. Bare LaTeX stays unchanged. */
export function pastedLatex(source: string) {
  const trimmed = source.trim()
  const delimiters = [
    ['$$', '$$'],
    ['\\[', '\\]'],
    ['\\(', '\\)'],
    ['$', '$'],
  ] as const
  for (const [open, close] of delimiters) {
    if (trimmed.length < open.length + close.length || !trimmed.startsWith(open) || !trimmed.endsWith(close)) continue
    return trimmed.slice(open.length, -close.length).trim()
  }
  return source
}
