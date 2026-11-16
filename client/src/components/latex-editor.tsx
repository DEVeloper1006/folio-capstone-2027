/**
 * Show one formula as static KaTeX until it is activated, then as a MathLive field. Notebook cells and inline markdown expressions share this surface. Contains the static renderer, the MathLive host, and the expression-command menu.
 *
 * @file
 */

import { useId, useRef, useState } from 'react'
import type { KeyboardEvent as ReactKeyboardEvent } from 'react'
import katex from 'katex'
import type { MathfieldElement } from 'mathlive'
import { expandMathfieldAliases, useExpressionCommands, useMathLive } from '#/editor/index.ts'
import { ExpressionCommandMenuView } from './expression-command-menu-view.tsx'
import './latex-editor.css'

/** Supply the formula and the callbacks for editing it. `startEditing` opens MathLive immediately; otherwise a click or Enter replaces the static formula. */
interface LatexEditorProps {
  initialLatex: string
  onLatexChange: (latex: string) => void
  label?: string
  /** `cell` fills a notebook row. `inline` sits inside a sentence. */
  layout?: 'cell' | 'inline'
  startEditing?: boolean
  /** Enter commits the formula. Shift+Enter stays with MathLive. Omit this on a notebook cell so Enter is not captured. */
  onCommit?: (latex: string) => void
  /** Escape leaves the formula without committing. Omit this on a notebook cell. */
  onCancel?: () => void
  /** Left at the start, or Right at the end, leaves an inline formula and returns its current LaTeX. */
  onBoundary?: (edge: 'start' | 'end', latex: string) => void
  /** Where the caret sits when an inline formula opens. A notebook cell ignores this. */
  caretEdge?: 'start' | 'end'
}

/** Receive the formula to display and the callback that mounts its editor. */
interface StaticLatexProps {
  latex: string
  label: string
  onEdit: () => void
}

/** Turn stored LaTeX into HTML the server and the browser can both produce. Invalid LaTeX is shown as source text. Display mode is for a notebook cell; inline math stays in the text line. */
export function renderLatexMarkup(latex: string, displayMode = true) {
  return katex.renderToString(latex, { displayMode, throwOnError: false, output: 'html' })
}

/** Show a formula as static KaTeX, or mount the same MathLive field a notebook cell uses once editing starts. */
export function LatexEditor({ initialLatex, onLatexChange, label = 'LaTeX expression', layout = 'cell', startEditing = false, onCommit, onCancel, onBoundary, caretEdge }: LatexEditorProps) {
  const [isEditing, setIsEditing] = useState(startEditing)

  /** Replace the static formula with the MathLive field. */
  function beginEditing() {
    setIsEditing(true)
  }

  if (!isEditing) return <StaticLatex latex={initialLatex} label={label} onEdit={beginEditing} />
  return <LatexMathfield initialLatex={initialLatex} onLatexChange={onLatexChange} label={label} layout={layout} onCommit={onCommit} onCancel={onCancel} onBoundary={onBoundary} caretEdge={caretEdge} />
}

/** Connect one activated formula to MathLive, expression commands, and optional Enter, Escape, and arrow-boundary callbacks. */
function LatexMathfield({ initialLatex, onLatexChange, label, layout, onCommit, onCancel, onBoundary, caretEdge = 'start' }: LatexEditorProps) {
  const onCommitRef = useRef(onCommit)
  const onCancelRef = useRef(onCancel)
  const onBoundaryRef = useRef(onBoundary)
  const caretEdgeRef = useRef(caretEdge)
  onCommitRef.current = onCommit
  onCancelRef.current = onCancel
  onBoundaryRef.current = onBoundary
  caretEdgeRef.current = caretEdge
  const fieldId = useId()
  const commands = useExpressionCommands()

  /** Forward the formula without the field id. The notebook cell adds its own id before storing the edit. */
  function reportLatexChange(_fieldId: string, latex: string) {
    onLatexChange(latex)
  }

  /** Fit an inline formula to the text line, then place the caret at the edge the sentence requested. */
  function configureMathfield(mathfield: MathfieldElement) {
    if (layout !== 'inline') return
    const container = mathfield.shadowRoot?.querySelector('.ML__container')
    if (container instanceof HTMLElement) {
      container.style.minHeight = '0'
      container.style.padding = '0'
      container.style.width = 'auto'
      container.style.alignItems = 'baseline'
    }
    mathfield.position = caretEdgeRef.current === 'end' ? mathfield.lastOffset : 0
  }

  /** Let expression commands consume `/` first. Enter commits an inline formula, Escape cancels it, and Left or Right at the formula’s edge returns to the sentence. */
  function handleEditorKeyDown(mathfield: MathfieldElement, event: KeyboardEvent) {
    if (commands.handleEditorKeyDown(mathfield, event)) return true
    if (onBoundaryRef.current !== undefined && isPlainHorizontalArrow(event) && mathfield.selectionIsCollapsed) {
      const atStart = event.key === 'ArrowLeft' && mathfield.position === 0
      const atEnd = event.key === 'ArrowRight' && mathfield.position === mathfield.lastOffset
      if (atStart || atEnd) {
        onBoundaryRef.current(atStart ? 'start' : 'end', expandMathfieldAliases(mathfield.value))
        return true
      }
    }
    if (event.key === 'Enter' && !event.shiftKey && onCommitRef.current !== undefined) {
      const latex = expandMathfieldAliases(mathfield.value).trim()
      if (latex.length === 0) onCancelRef.current?.()
      else onCommitRef.current(latex)
      return true
    }
    if (event.key === 'Escape' && onCancelRef.current !== undefined) {
      onCancelRef.current()
      return true
    }
    return false
  }

  const editorHostRef = useMathLive({
    cellId: fieldId,
    initialLatex,
    onLatexChange: reportLatexChange,
    onEditorKeyDown: handleEditorKeyDown,
    focusOnMount: true,
    label,
    configureMathfield,
  })
  const editorClass = layout === 'inline' ? 'latex-editor-inline' : 'cell-editor'
  const fieldClass = layout === 'inline' ? 'latex-editor-inline-field' : 'cell-input'

  return (
    <div className={editorClass}>
      <div className={fieldClass} ref={editorHostRef} />
      {commands.isOpen ? <ExpressionCommandMenuView menu={commands} /> : null}
    </div>
  )
}

/** Recognize Left or Right without Shift, Alt, or a platform modifier, so selection and structural shortcuts stay inside the formula. */
function isPlainHorizontalArrow(event: KeyboardEvent) {
  return (event.key === 'ArrowLeft' || event.key === 'ArrowRight') && !event.shiftKey && !event.altKey && !event.metaKey && !event.ctrlKey && !event.isComposing
}

/** Render a formula with KaTeX and activate the editor from a click, Enter, or Space. */
function StaticLatex({ latex, label, onEdit }: StaticLatexProps) {
  const markup = renderLatexMarkup(latex)

  /** Activate the formula from Enter or Space. */
  function handleKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (event.key !== 'Enter' && event.key !== ' ') return
    event.preventDefault()
    onEdit()
  }

  return <div className="static-latex" role="button" tabIndex={0} aria-label={label} dangerouslySetInnerHTML={{ __html: markup }} onClick={onEdit} onKeyDown={handleKeyDown} />
}
