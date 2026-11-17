/**
 * Render one LaTeX cell. Keep inactive cells rendered; use literal LaTeX or MathLive only while editing, according to the page's mode.
 *
 * @file
 */

import { useEffect, useState } from 'react'
import { preloadMathLive } from '#/editor/index.ts'
import { SourceField } from '#/component-library/source-field'
import type { CellEditorMode } from '#/notebook/page'
import { MarkdownDocument } from './markdown-cell'
import { LatexEditor } from './latex-editor.tsx'

/** Supply the cell's identity, starting LaTeX, and notebook edit callback. `readOnly` shows the formula and does not mount MathLive. */
interface LatexCellProps {
  caption?: string
  onCaptionChange?: (caption: string) => void
  previous?: string
  cellId: string
  editorMode?: CellEditorMode
  initialLatex: string
  onLatexChange: (cellId: string, latex: string) => void
  editing?: boolean
  onBeginEditing?: () => void
  readOnly?: boolean
}

/** Render one notebook formula and report its edits with this cell's id. A read-only cell ignores activation. */
export function LatexCell({ caption = '', onCaptionChange, editorMode = 'rich', previous, cellId, initialLatex, onLatexChange, editing, onBeginEditing, readOnly = false }: LatexCellProps) {
  useEffect(preloadMathLive, [])
  const [localEditing, setLocalEditing] = useState(false)
  const active = editing ?? localEditing
  /** Open the page's chosen editor while keeping inactive cells rendered. */
  function beginEditing() {
    if (onBeginEditing) onBeginEditing()
    else setLocalEditing(true)
  }
  /** Return a standalone source editor to its rendered preview. Notebook commands own controlled editing. */
  function finishEditing() {
    setLocalEditing(false)
  }

  /** Store the edited formula on this cell. */
  function reportLatexChange(latex: string) {
    onLatexChange(cellId, latex)
  }

  return (
    <>
      {active && !readOnly && onCaptionChange ? (
        <input className="math-cell-caption" aria-label="Math cell caption" placeholder="Add caption" value={caption} onChange={(event) => onCaptionChange(event.target.value)} />
      ) : (
        caption.trim() && (
          <div className="math-cell-caption">
            <MarkdownDocument markdown={caption} />
          </div>
        )
      )}
      {editorMode === 'source' && active && !readOnly ? (
        <SourceField previous={previous} value={initialLatex} onChange={reportLatexChange} label="LaTeX source" onFinish={editing === undefined ? finishEditing : undefined} />
      ) : (
        <LatexEditor previous={previous} editing={active && editorMode === 'rich'} onBeginEditing={beginEditing} initialLatex={initialLatex} onLatexChange={reportLatexChange} readOnly={readOnly} label="LaTeX cell" layout="cell" />
      )}
    </>
  )
}
