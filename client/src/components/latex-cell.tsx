/**
 * Render one LaTeX cell. Shows the shared formula surface: static KaTeX until the cell is activated, then the MathLive editor.
 *
 * @file
 */

import { useEffect } from 'react'
import { preloadMathLive } from '#/editor/index.ts'
import { LatexEditor } from './latex-editor.tsx'

/** Supply the cell's identity, starting LaTeX, and notebook edit callback. */
interface LatexCellProps {
  cellId: string
  initialLatex: string
  onLatexChange: (cellId: string, latex: string) => void
}

/** Render one notebook formula and report its edits with this cell's id. */
export function LatexCell({ cellId, initialLatex, onLatexChange }: LatexCellProps) {
  useEffect(preloadMathLive, [])

  /** Store the edited formula on this cell. */
  function reportLatexChange(latex: string) {
    onLatexChange(cellId, latex)
  }

  return <LatexEditor initialLatex={initialLatex} onLatexChange={reportLatexChange} label="LaTeX cell" layout="cell" />
}
