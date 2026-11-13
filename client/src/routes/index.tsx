/**
 * Display the cursor playground at the home route. Contains the movement guide, editable sample cells, in-memory notebook state, and the Add cell action.
 *
 * @file
 */

import { createFileRoute } from '@tanstack/react-router'
import { useCallback, useState } from 'react'
import { LatexCell } from '#/components/latex-cell'
import { sampleExpressions } from '#/editor/sample-expressions'

export const Route = createFileRoute('/')({ component: NotebookPage })

/** Keep one playground cell's stable identity, display title, and current LaTeX in React memory. */
interface NotebookCell {
  cellId: number
  title: string
  latex: string
}

/** Render the editable sample notebook and movement guide, holding each cell’s LaTeX in React memory until the page reloads. */
function NotebookPage() {
  /** Create the initial notebook cells from the sample expressions once when the page mounts. */
  const createInitialCells = () => {
    /** Assign each sample a stable numeric cell identifier. */
    const createSampleCell = (sampleExpression: Omit<NotebookCell, 'cellId'>, cellId: number) => ({ ...sampleExpression, cellId })
    return sampleExpressions.map(createSampleCell)
  }

  const [cells, setCells] = useState(createInitialCells)

  /** Replace the stored LaTeX for the edited cell while preserving every other cell. */
  const updateCellLatex = (cellId: number, latex: string) => {
    /** Compute the next notebook state from the latest cell array so concurrent React updates are retained. */
    const replaceCellLatex = (currentCells: NotebookCell[]) => {
      /** Update only the cell whose identifier matches the edit. */
      const updateMatchingCell = (cell: NotebookCell) => (cell.cellId === cellId ? { ...cell, latex } : cell)
      return currentCells.map(updateMatchingCell)
    }

    setCells(replaceCellLatex)
  }

  const handleLatexChange = useCallback(updateCellLatex, [])

  /** Append an empty editable cell when the Add cell button is clicked. */
  const handleAddCell = () => {
    /** Allocate the next cell identifier and preserve all existing notebook entries. */
    const appendEmptyCell = (currentCells: NotebookCell[]) => [...currentCells, { cellId: currentCells.length, title: 'Blank cell', latex: '' }]
    return setCells(appendEmptyCell)
  }

  /** Render the cell number, example title, and editable LaTeX field for this notebook entry. */
  const renderCell = (cell: NotebookCell, cellIndex: number) => (
    <div className="cell" key={cell.cellId}>
      <span className="cell-number" aria-hidden="true">
        {String(cellIndex + 1).padStart(2, '0')}
      </span>
      <div className="cell-content">
        <p className="cell-title">{cell.title}</p>
        <LatexCell cellId={cell.cellId} initialLatex={cell.latex} onLatexChange={handleLatexChange} />
      </div>
    </div>
  )

  return (
    <main className="notebook" aria-label="LaTeX notebook">
      <header className="notebook-intro">
        <h1>Cursor playground</h1>
        <p>20 expressions to explore. Edits reset when you refresh.</p>
        <details>
          <summary>Movement keys</summary>
          <dl className="movement-keys">
            <dt>Arrow keys</dt>
            <dd>← / → enter the numerator or superscript and exit the structure horizontally. ↑ / ↓ change related regions and remember your previous position.</dd>
            <dt>Option + ← / →</dt>
            <dd>Skip a complete term within the current slot.</dd>
            <dt>Option + ↑ / ↓</dt>
            <dd>Leave a structure / enter its first slot.</dd>
            <dt>Shift + arrows</dt>
            <dd>← / → select complete structures when crossing their boundaries; reversing returns inside. ↑ / ↓ select toward a region’s beginning / end, then expand outward.</dd>
            <dt>Tab / Shift + Tab</dt>
            <dd>Visit unfilled placeholders forward / backward, then exit a region. Matrices and piecewise expressions visit their neighboring cells.</dd>
            <dt>/ in an empty region</dt>
            <dd>Search expression templates. ↑ / ↓ select, → shows variants, ← returns, Enter inserts, and Escape cancels. Slash after existing math still creates a fraction.</dd>
            <dt>Home / End</dt>
            <dd>Move to the current region’s beginning / end. Hold Shift to select; Control + Home / End targets the whole expression.</dd>
            <dt>Shift + Option + ← / →</dt>
            <dd>Extend the selection by complete terms.</dd>
            <dt>Shift + Option + ↑ / ↓</dt>
            <dd>Grow through a symbol, function call, clause, and enclosing expression / restore the exact previous selection.</dd>
          </dl>
          <p>Movement follows DesQuill’s visual-arrow policy, extended to matrix and piecewise rows. Mouse dragging uses MathLive’s native selection. Integrands and operator bodies remain ordinary rows rather than semantic arguments.</p>
        </details>
      </header>
      {cells.map(renderCell)}
      <button type="button" className="add-cell" onClick={handleAddCell}>
        + Add cell
      </button>
    </main>
  )
}
