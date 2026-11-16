/**
 * Render one LaTeX cell. Shows server-rendered KaTeX until the cell is activated, then mounts the MathLive editor.
 *
 * @file
 */

import { useEffect, useState } from 'react'
import type { KeyboardEvent } from 'react'
import katex from 'katex'
import { useExpressionCommands, preloadMathLive, useMathLive } from '#/editor/index.ts'
import { ExpressionCommandMenuView } from './expression-command-menu-view'
import './static-latex.css'

/** Supply the cell's identity, starting LaTeX, and notebook edit callback. */
interface LatexCellProps {
  cellId: string
  initialLatex: string
  onLatexChange: (cellId: string, latex: string) => void
}

/** Receive the formula to display and the callback that mounts its editor. */
interface StaticLatexProps {
  latex: string
  onEdit: () => void
}

/** Render static mathematics, and replace it with the editor when the cell is activated. */
export function LatexCell({ cellId, initialLatex, onLatexChange }: LatexCellProps) {
  const [isEditing, setIsEditing] = useState(false)
  useEffect(preloadMathLive, [])

  /** Mount the MathLive editor for this cell. */
  function beginEditing() {
    setIsEditing(true)
  }

  if (isEditing) return <LatexEditor cellId={cellId} initialLatex={initialLatex} onLatexChange={onLatexChange} />
  return <StaticLatex latex={initialLatex} onEdit={beginEditing} />
}

/** Connect an activated cell to MathLive and focus it so typing starts immediately. */
function LatexEditor({ cellId, initialLatex, onLatexChange }: LatexCellProps) {
  const commands = useExpressionCommands()
  const editorHostRef = useMathLive({
    cellId,
    initialLatex,
    onLatexChange,
    onEditorKeyDown: commands.handleEditorKeyDown,
    focusOnMount: true,
  })

  return (
    <div className="cell-editor">
      <div className="cell-input" ref={editorHostRef} />
      {commands.isOpen && <ExpressionCommandMenuView menu={commands} />}
    </div>
  )
}

/** Render a formula with KaTeX and activate the editor from a click or keyboard. */
function StaticLatex({ latex, onEdit }: StaticLatexProps) {
  const markup = renderLatexMarkup(latex)

  /** Activate the cell from Enter or Space. */
  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key !== 'Enter' && event.key !== ' ') return
    event.preventDefault()
    onEdit()
  }

  return <div className="static-latex" role="button" tabIndex={0} aria-label="LaTeX cell" dangerouslySetInnerHTML={{ __html: markup }} onClick={onEdit} onKeyDown={handleKeyDown} />
}

/** Turn stored LaTeX into HTML the server and the browser can both produce. Invalid LaTeX is shown as source text. */
function renderLatexMarkup(latex: string) {
  return katex.renderToString(latex, { displayMode: true, throwOnError: false, output: 'html' })
}
