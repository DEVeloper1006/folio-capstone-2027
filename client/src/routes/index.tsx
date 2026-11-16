/**
 * Display the mixed math and Markdown notebook at the home route. Contains the sample page and in-memory source updates.
 *
 * @file
 */

import { createFileRoute } from '@tanstack/react-router'
import { useCallback, useState } from 'react'
import { PageView } from '#/components/page-view'
import { createSamplePage } from '#/notebook/sample-page.ts'
import type { NotebookCell } from '#/notebook/notebook-cells.ts'
import type { Page } from '#/notebook/page.ts'

export const Route = createFileRoute('/')({ component: NotebookPage })

/** Render the sample page, retaining its cells in React memory until the page reloads. */
function NotebookPage() {
  const [page, setPage] = useState(createSamplePage)

  /** Replace the stored LaTeX for the edited cell while preserving every other cell. */
  const updateCellLatex = (cellId: string, latex: string) => {
    /** Compute the next notebook state from the latest cell array so concurrent React updates are retained. */
    const replaceCellLatex = (currentPage: Page) => {
      /** Update only the cell whose identifier matches the edit. */
      const updateMatchingCell = (cell: NotebookCell) => (cell.cellId === cellId && cell.kind === 'math' ? { ...cell, latex } : cell)
      return { ...currentPage, cells: currentPage.cells.map(updateMatchingCell) }
    }

    setPage(replaceCellLatex)
  }

  const handleLatexChange = useCallback(updateCellLatex, [])

  /** Replace only a Markdown cell's source so preview toggling never changes its stored content or neighboring mathematical editors. */
  const updateCellMarkdown = (cellId: string, markdown: string) => {
    /** Apply a Markdown edit against the latest notebook state. */
    const replaceCellMarkdown = (currentPage: Page) => {
      /** Preserve cell identity and leave other cell types untouched. */
      const updateMatchingCell = (cell: NotebookCell) => (cell.cellId === cellId && cell.kind === 'markdown' ? { ...cell, markdown } : cell)
      return { ...currentPage, cells: currentPage.cells.map(updateMatchingCell) }
    }
    setPage(replaceCellMarkdown)
  }

  const handleMarkdownChange = useCallback(updateCellMarkdown, [])

  return (
    <main className={`notebook notebook-${page.pageMetadata.width}`} aria-label="Folio notebook">
      <PageView page={page} onLatexChange={handleLatexChange} onMarkdownChange={handleMarkdownChange} />
    </main>
  )
}
