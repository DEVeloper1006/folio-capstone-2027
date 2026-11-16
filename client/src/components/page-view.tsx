/**
 * Render one notebook page. Contains the ordered cells, the spacing and width from page metadata, and the actions that append a cell.
 *
 * @file
 */

import type { CSSProperties } from 'react'
import { Button } from '#/component-library/index.ts'
import { LatexCell } from './latex-cell'
import { MarkdownCell } from './markdown-cell'
import { PageMenuView } from './page-menu-view'
import type { NotebookCell } from '#/notebook/notebook-cells.ts'
import type { Page, PageMetadata } from '#/notebook/page.ts'

/** Receive the page to display and the notebook callbacks that change its cells. */
interface PageViewProps {
  page: Page
  onLatexChange: (cellId: string, latex: string) => void
  onMarkdownChange: (cellId: string, markdown: string) => void
  onAddMathCell: () => void
  onAddMarkdownCell: () => void
  onPageMetadataChange: (pageMetadata: PageMetadata) => void
}

/** Render the editor that matches a cell's kind. */
function renderCell(cell: NotebookCell, onLatexChange: PageViewProps['onLatexChange'], onMarkdownChange: PageViewProps['onMarkdownChange']) {
  return (
    <div className="cell" key={cell.cellId}>
      {cell.kind === 'math' ? <LatexCell cellId={cell.cellId} initialLatex={cell.latex} onLatexChange={onLatexChange} /> : <MarkdownCell cellId={cell.cellId} markdown={cell.markdown} onMarkdownChange={onMarkdownChange} />}
    </div>
  )
}

/** Show the page's cells at the configured width and spacing, and append an empty math or Markdown cell. */
export function PageView({ page, onLatexChange, onMarkdownChange, onAddMathCell, onAddMarkdownCell, onPageMetadataChange }: PageViewProps) {
  const cellListStyle: CSSProperties = { gap: page.pageMetadata.cellSpacingPx }

  /** Render one cell with the page's edit callbacks. */
  function renderPageCell(cell: NotebookCell) {
    return renderCell(cell, onLatexChange, onMarkdownChange)
  }

  return (
    <section className="page" aria-label={page.pageMetadata.title} style={cellListStyle}>
      <PageMenuView pageMetadata={page.pageMetadata} onPageMetadataChange={onPageMetadataChange} />
      {page.cells.map(renderPageCell)}
      <div className="add-cell-actions" aria-label="Add a notebook cell">
        <Button variant="quiet" onClick={onAddMathCell}>
          + Math
        </Button>
        <Button variant="quiet" onClick={onAddMarkdownCell}>
          + Markdown
        </Button>
      </div>
    </section>
  )
}
