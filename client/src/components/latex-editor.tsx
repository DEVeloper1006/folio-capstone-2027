/**
 * Show one formula as static KaTeX until it is activated, then as a MathLive field. Notebook cells and inline markdown expressions share this surface. Contains the static renderer, pointer-selection handoff, the MathLive host, and expression menus.
 *
 * @file
 */

import { useEffect, useId, useRef, useState } from 'react'
import type { KeyboardEvent as ReactKeyboardEvent, PointerEvent as ReactPointerEvent } from 'react'
import katex from 'katex'
import { previewMacros } from '#/editor/mathlive/mathfield-macros'
import type { MathfieldElement } from 'mathlive'
import { expandMathfieldAliases, useExpressionCommands, useMathLive } from '#/editor/index.ts'
import { ExpressionSelectionMenu } from './expression-selection-menu.tsx'
import { ExpressionCommandMenuView } from './expression-command-menu-view.tsx'
import './latex-editor.css'

/** Supply the formula and the callbacks for editing it. `startEditing` opens MathLive immediately; otherwise a click or Enter replaces the static formula. `readOnly` keeps the static formula and does not accept a click. */
interface LatexEditorProps {
  initialLatex: string
  onLatexChange: (latex: string) => void
  readOnly?: boolean
  label?: string
  /** `cell` fills a notebook row. `inline` sits inside a sentence. */
  layout?: 'cell' | 'inline'
  editing?: boolean
  onBeginEditing?: () => void
  startEditing?: boolean
  /** Enter commits the formula. Shift+Enter stays with MathLive. Omit this on a notebook cell so Enter is not captured. */
  onCommit?: (latex: string) => void
  /** Escape leaves the formula without committing. Omit this on a notebook cell. */
  onCancel?: () => void
  /** Left at the start, or Right at the end, leaves an inline formula and returns its current LaTeX. */
  onBoundary?: (edge: 'start' | 'end', latex: string) => void
  /** Where the caret sits when an inline formula opens. A notebook cell ignores this. */
  caretEdge?: 'start' | 'end'
  /** Apply the pointer's initial selection after the editor replaces its static preview. */
  onMount?: (mathfield: MathfieldElement) => void
}

/** Receive the formula to display and the callback that mounts its editor. */
interface StaticLatexProps {
  latex: string
  label: string
  onEdit: () => void
  onPointerDown: (event: ReactPointerEvent<HTMLDivElement>) => void
}

/** Turn stored LaTeX into HTML the server and the browser can both produce. Invalid LaTeX is shown as source text. Display mode is for a notebook cell; inline math stays in the text line. */
export function renderLatexMarkup(latex: string, displayMode = true) {
  return katex.renderToString(latex, { displayMode, throwOnError: false, output: 'html', macros: { ...previewMacros } })
}

/** Show stored LaTeX as KaTeX without a control that starts editing. */
function StaticLatexMarkup({ latex, label }: { latex: string; label: string }) {
  const markup = renderLatexMarkup(latex)
  return <div className="static-latex is-view" aria-label={label} dangerouslySetInnerHTML={{ __html: markup }} />
}

/** Continue a drag across the static-to-editable transition using MathLive's public coordinate lookup. */
function usePreviewSelection(editing: boolean, beginEditing: () => void) {
  const field = useRef<MathfieldElement | null>(null)
  const drag = useRef<{ x: number; y: number; endX: number; endY: number; active: boolean } | null>(null)

  /** Map both pointer endpoints to the mounted formula without changing its source. */
  function applyDrag() {
    const current = drag.current
    const mathfield = field.current
    if (!current || !mathfield?.isConnected) return
    const anchor = mathfield.getOffsetFromPoint(current.x, current.y)
    const focus = mathfield.getOffsetFromPoint(current.endX, current.endY)
    mathfield.selection = { ranges: [[Math.min(anchor, focus), Math.max(anchor, focus)]], direction: focus < anchor ? 'backward' : 'forward' }
    if (!current.active) drag.current = null
  }

  /** Activate MathLive before a browser text selection can start. */
  function beginPointerSelection(event: ReactPointerEvent<HTMLDivElement>) {
    if (event.button !== 0 || event.ctrlKey || event.metaKey || event.altKey) return
    event.preventDefault()
    drag.current = { x: event.clientX, y: event.clientY, endX: event.clientX, endY: event.clientY, active: true }
    beginEditing()
  }

  /** Restore the pointer selection once MathLive has laid out its glyphs. */
  function mountSelection(mathfield: MathfieldElement) {
    field.current = mathfield
    requestAnimationFrame(applyDrag)
  }

  /** Keep a preview drag alive even after its original DOM element has been replaced. */
  function trackDrag() {
    if (!editing) return
    /** Update the selection as the pointer moves, and finish it on release. */
    function move(event: PointerEvent) {
      if (!drag.current?.active) return
      drag.current.endX = event.clientX
      drag.current.endY = event.clientY
      drag.current.active = event.type === 'pointermove' && event.buttons !== 0
      applyDrag()
    }
    document.addEventListener('pointermove', move)
    document.addEventListener('pointerup', move)
    document.addEventListener('pointercancel', move)
    /** Remove document listeners when the cell leaves edit mode. */
    function stopTracking() {
      document.removeEventListener('pointermove', move)
      document.removeEventListener('pointerup', move)
      document.removeEventListener('pointercancel', move)
      drag.current = null
      field.current = null
    }
    return stopTracking
  }
  useEffect(trackDrag, [editing])
  return { beginPointerSelection, mountSelection }
}

/** Show a formula as static KaTeX, or mount the same MathLive field a notebook cell uses once editing starts. A read-only formula never mounts MathLive. */
export function LatexEditor({ initialLatex, onLatexChange, readOnly = false, label = 'LaTeX expression', layout = 'cell', startEditing = false, editing, onBeginEditing, onCommit, onCancel, onBoundary, caretEdge }: LatexEditorProps) {
  const [isEditing, setIsEditing] = useState(startEditing && !readOnly)

  /** Replace the static formula with the MathLive field. */
  function beginEditing() {
    if (onBeginEditing) onBeginEditing()
    else setIsEditing(true)
  }

  const active = editing ?? isEditing
  const { beginPointerSelection, mountSelection } = usePreviewSelection(active, beginEditing)

  if (readOnly) return <StaticLatexMarkup latex={initialLatex} label={label} />
  if (!active) return <StaticLatex latex={initialLatex} label={label} onEdit={beginEditing} onPointerDown={beginPointerSelection} />
  return <LatexMathfield initialLatex={initialLatex} onLatexChange={onLatexChange} label={label} layout={layout} onCommit={onCommit} onCancel={onCancel} onBoundary={onBoundary} caretEdge={caretEdge} onMount={mountSelection} />
}

/** Connect one activated formula to MathLive, expression commands, and optional Enter, Escape, and arrow-boundary callbacks. */
function LatexMathfield({ initialLatex, onLatexChange, label, layout, onCommit, onCancel, onBoundary, caretEdge = 'start', onMount }: LatexEditorProps) {
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

  /** Restore a preview pointer selection; fit inline math to its text line and place its initial caret at the requested edge. */
  function configureMathfield(mathfield: MathfieldElement) {
    onMount?.(mathfield)
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

  /** Let expression commands consume `\` first. Enter commits an inline formula, Escape cancels it, and Left or Right at the formula’s edge returns to the sentence. */
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
      {commands.isOpen ? <ExpressionCommandMenuView menu={commands} /> : <ExpressionSelectionMenu hostRef={editorHostRef} />}
    </div>
  )
}

/** Recognize Left or Right without Shift, Alt, or a platform modifier, so selection and structural shortcuts stay inside the formula. */
function isPlainHorizontalArrow(event: KeyboardEvent) {
  return (event.key === 'ArrowLeft' || event.key === 'ArrowRight') && !event.shiftKey && !event.altKey && !event.metaKey && !event.ctrlKey && !event.isComposing
}

/** Render KaTeX and activate MathLive from a pointer press, Enter, or Space, preserving pointer drags. */
function StaticLatex({ latex, label, onEdit, onPointerDown }: StaticLatexProps) {
  const markup = renderLatexMarkup(latex)

  /** Activate the formula from Enter or Space. */
  function handleKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (event.key !== 'Enter' && event.key !== ' ') return
    event.preventDefault()
    onEdit()
  }

  return <div className="static-latex" role="button" tabIndex={0} aria-label={label} dangerouslySetInnerHTML={{ __html: markup }} onPointerDown={onPointerDown} onKeyDown={handleKeyDown} />
}
