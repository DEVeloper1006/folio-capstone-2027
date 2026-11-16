/**
 * Render one LaTeX cell. Shows the shared formula surface: static KaTeX until the cell is activated, then the MathLive editor.
 *
 * @file
 */

import { useEffect } from 'react'
import { preloadMathLive } from '#/editor/index.ts'
import { LatexEditor } from './latex-editor.tsx'

/** Supply the cell's identity, starting LaTeX, and notebook edit callback. `readOnly` shows the formula and does not mount MathLive. */
interface LatexCellProps {
  cellId: string
  initialLatex: string
  onLatexChange: (cellId: string, latex: string) => void
  editing?: boolean
  onBeginEditing?: () => void
  readOnly?: boolean
}

/** Render one notebook formula and report its edits with this cell's id. A read-only cell ignores activation. */
export function LatexCell({ cellId, initialLatex, onLatexChange, editing, onBeginEditing, readOnly = false }: LatexCellProps) {
  useEffect(preloadMathLive, [])

  /** Store the edited formula on this cell. */
  function reportLatexChange(latex: string) {
    onLatexChange(cellId, latex)
  }

  return <LatexEditor editing={editing} onBeginEditing={onBeginEditing} initialLatex={initialLatex} onLatexChange={reportLatexChange} readOnly={readOnly} label="LaTeX cell" layout="cell" />
}
