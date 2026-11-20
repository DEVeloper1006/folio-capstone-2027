/**
 * Define the notebook's supported cells: editable mathematics, Markdown prose, and graph images with their editable source and captured view. Contains stable UUID identity and clipboard text extraction.
 *
 * @file
 */

import type { GraphDocument, GraphSnapshot } from '#/graph/graph-model'

/** Keep a cell's stable identifier independent of the editor used to display it. */
interface CellIdentity {
  cellId: string
  /** Preorder nesting level; omitted on older pages means a top-level block. */
  depth?: number
  /** Optional subject assigned to this problem section; children inherit it. */
  mathMode?: string
}

/** Create a new cell identifier. Sample pages use fixed identifiers so server and browser renders match. */
export function createCellId() {
  return crypto.randomUUID()
}

/** Store editable LaTeX in a mathematical cell backed by MathLive. */
export interface MathNotebookCell extends CellIdentity {
  kind: 'math'
  caption?: string
  latex: string
}

/** Store Markdown source independently of whether the cell is being edited or rendered. */
export interface MarkdownNotebookCell extends CellIdentity {
  kind: 'markdown'
  markdown: string
}

/** Select an editor by cell kind while retaining the original source for each supported content format. */
export type NotebookCell = MathNotebookCell | MarkdownNotebookCell | GraphNotebookCell

/** Keep an inserted image and its editable graph together, independent of the page's scratch graph. */
export interface GraphNotebookCell extends CellIdentity {
  kind: 'graph'
  graph: GraphDocument
  snapshot: GraphSnapshot
}

/** Copy graph equations as text without exposing the embedded image data. */
export function cellSource(cell: NotebookCell) {
  if (cell.kind === 'math') return cell.latex
  if (cell.kind === 'markdown') return cell.markdown
  /** Retain the current dimension's equations in display order. */
  function equation(row: GraphDocument['expressions']['2d'][number]) {
    return row.source
  }
  return cell.graph.expressions[cell.graph.dimension].map(equation).join('\n')
}

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
