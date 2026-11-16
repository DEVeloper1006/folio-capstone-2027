/**
 * Render one notebook page. Contains the ordered cells at the spacing and width stored in the page metadata.
 *
 * @file
 */

import type { CSSProperties } from 'react'
import { LatexCell } from './latex-cell'
import { MarkdownCell } from './markdown-cell'
import type { NotebookCell } from '#/notebook/notebook-cells.ts'
import type { Page } from '#/notebook/page.ts'

/** Receive the page to display and the callbacks that store edits to its cells. */
interface PageViewProps {
  page: Page
  onLatexChange: (cellId: string, latex: string) => void
  onMarkdownChange: (cellId: string, markdown: string) => void
}

/** Render the editor that matches a cell's kind. */
function renderCell(cell: NotebookCell, onLatexChange: PageViewProps['onLatexChange'], onMarkdownChange: PageViewProps['onMarkdownChange']) {
  return (
    <div className="cell" key={cell.cellId}>
      {cell.kind === 'math' ? <LatexCell cellId={cell.cellId} initialLatex={cell.latex} onLatexChange={onLatexChange} /> : <MarkdownCell cellId={cell.cellId} markdown={cell.markdown} onMarkdownChange={onMarkdownChange} />}
    </div>
  )
}

/** Show only the page's cells, using its stored spacing and leaving width to the notebook container. */
export function PageView({ page, onLatexChange, onMarkdownChange }: PageViewProps) {
  const cellListStyle: CSSProperties = { gap: page.pageMetadata.cellSpacingPx }

  /** Render one cell with the page's edit callbacks. */
  function renderPageCell(cell: NotebookCell) {
    return renderCell(cell, onLatexChange, onMarkdownChange)
  }

  return (
    <section className="page" aria-label={page.pageMetadata.title} style={cellListStyle}>
      {page.cells.map(renderPageCell)}
    </section>
  )
}
