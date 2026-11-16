/**
 * Build the opening notebook page. Contains the default display metadata and one Markdown note followed by the sample math cells.
 *
 * @file
 */

import { sampleExpressions } from '#/editor/index.ts'
import type { MathNotebookCell, NotebookCell } from './notebook-cells.ts'
import type { Page } from './page.ts'

/** Use the current centered notebook column and a short gap between cells. */
const defaultPageMetadata = {
  title: 'Notebook playground',
  cellSpacingPx: 16,
  width: 'regular',
} as const

const openingNote = `## Make room for the reasoning

A notebook needs the **why** as well as the working. Use a text cell to state the problem, explain a step, or leave a question for later.

- Define your assumptions, such as $x \\in \\mathbb{R}$.
- Work through the calculation in a math cell below.
- Come back here to explain what the result means.

> Try **Edit** to see the Markdown behind this note.`

/** Build a fixed UUID for a sample cell. The same index always returns the same identifier. */
function sampleCellId(cellIndex: number) {
  return `00000000-0000-4000-8000-${cellIndex.toString(16).padStart(12, '0')}`
}

/** Assign each sample expression a math cell after the opening note. */
function createSampleCell(sampleExpression: { latex: string }, cellIndex: number): MathNotebookCell {
  return { cellId: sampleCellId(cellIndex + 1), kind: 'math', latex: sampleExpression.latex }
}

/** Return the in-memory page shown on first load, with both cell kinds and the default display metadata. */
export function createSamplePage(): Page {
  const cells: NotebookCell[] = [{ cellId: sampleCellId(0), kind: 'markdown', markdown: openingNote }, ...sampleExpressions.map(createSampleCell)]
  return { pageId: 'playground', cells, pageMetadata: defaultPageMetadata }
}
