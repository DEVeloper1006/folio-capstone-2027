/**
 * Show selected MathLive subexpressions beside their highlight with a LaTeX copy action. Contains selection observation, viewport positioning, dismissal, and the shared menu surface.
 *
 * @file
 */
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { PointerEvent, RefObject } from 'react'
import { createPortal } from 'react-dom'
import type { MathfieldElement } from 'mathlive'
import { Button } from '#/component-library/button'
import { CopyIcon } from '#/component-library/icons/folio-icons'
import { MathPreview } from '#/component-library/math-preview'
import { expandMathfieldAliases } from '#/editor/index'

/** Store selected source and the highlight's lower-right viewport corner. */
interface ExpressionSelection {
  latex: string[]
  x: number
  y: number
}

/** Preserve formula focus and selection for pointer actions. Keyboard users can still Tab to Copy. */
function keepSelection(event: PointerEvent) {
  event.preventDefault()
}

/** Follow one mounted editor's selected ranges; discard menu state when that editor closes. */
export function ExpressionSelectionMenu({ hostRef }: { hostRef: RefObject<HTMLDivElement | null> }) {
  const [selection, setSelection] = useState<ExpressionSelection | null>(null)
  const [notice, setNotice] = useState('')
  const menuRef = useRef<HTMLDivElement>(null)

  /** Observe selected source and glyph bounds after MathLive has painted. */
  function observeSelection() {
    const host = hostRef.current
    if (!host) return
    let frame = 0
    let dismissed = false
    /** Read exact LaTeX for each nonempty range, keeping discontinuous selections separate. */
    function update() {
      const field = host?.querySelector<MathfieldElement>('math-field')
      if (!field || field.selectionIsCollapsed) {
        setSelection(null)
        return
      }
      const latex: string[] = []
      for (const range of field.selection.ranges) {
        const start = Math.min(...range)
        const end = Math.max(...range)
        if (start === end) continue
        latex.push(expandMathfieldAliases(field.getValue([start, end], 'latex')))
      }
      // MathLive paints separate boxes for fractions and disjoint glyph regions.
      const bounds: DOMRect[] = []
      for (const element of field.shadowRoot?.querySelectorAll('.ML__selection') ?? []) {
        const rect = element.getBoundingClientRect()
        if (rect.width > 0 && rect.height > 0) bounds.push(rect)
      }
      if (!bounds.length || !latex.length) {
        setSelection(null)
        return
      }
      let right = 0
      let bottom = 0
      let visible = false
      for (const rect of bounds) {
        right = Math.max(right, rect.right)
        bottom = Math.max(bottom, rect.bottom)
        visible ||= rect.bottom > 0 && rect.top < window.innerHeight && rect.right > 0 && rect.left < window.innerWidth
      }
      if (!visible) {
        setSelection(null)
        return
      }
      setSelection({ latex, x: right + 12, y: bottom + 12 })
      setNotice('')
    }
    /** Wait for MathLive's queued render before measuring its painted selection boxes. */
    function afterPaint() {
      frame = requestAnimationFrame(update)
    }
    /** Coalesce selection, input, and scroll events into one geometry read after layout. */
    function schedule(event: Event) {
      if (event.type === 'selection-change' || event.type === 'input') dismissed = false
      if (dismissed) return
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(afterPaint)
    }
    /** Dismiss on outside interaction or Escape without consuming the editor's key handling. */
    function dismiss(event: Event) {
      if (event instanceof KeyboardEvent && event.key !== 'Escape') return
      const path = event.composedPath()
      if (event instanceof KeyboardEvent || (!path.includes(host!) && !path.includes(menuRef.current!))) {
        dismissed = true
        cancelAnimationFrame(frame)
        setSelection(null)
      }
    }
    host.addEventListener('selection-change', schedule)
    host.addEventListener('input', schedule)
    document.addEventListener('pointerdown', dismiss)
    document.addEventListener('keydown', dismiss)
    document.addEventListener('focusin', dismiss)
    window.addEventListener('scroll', schedule, true)
    window.addEventListener('resize', schedule)
    frame = requestAnimationFrame(afterPaint)
    /** Detach listeners and cancel pending geometry work when the editor closes. */
    function stopObserving() {
      cancelAnimationFrame(frame)
      host?.removeEventListener('selection-change', schedule)
      host?.removeEventListener('input', schedule)
      document.removeEventListener('pointerdown', dismiss)
      document.removeEventListener('keydown', dismiss)
      document.removeEventListener('focusin', dismiss)
      window.removeEventListener('scroll', schedule, true)
      window.removeEventListener('resize', schedule)
    }
    return stopObserving
  }
  useEffect(observeSelection, [hostRef])

  /** Use the requested 12px offset, clamping only when the menu would leave the viewport. */
  function positionMenu() {
    const menu = menuRef.current
    if (!menu || !selection) return
    const rect = menu.getBoundingClientRect()
    menu.style.left = `${Math.max(8, Math.min(selection.x, window.innerWidth - rect.width - 8))}px`
    menu.style.top = `${Math.max(8, Math.min(selection.y, window.innerHeight - rect.height - 8))}px`
  }
  useLayoutEffect(positionMenu, [selection, notice])

  /** Copy source LaTeX so fractions and powers survive pasting into another cell. */
  async function copy() {
    if (!selection) return
    try {
      await navigator.clipboard.writeText(selection.latex.join('\n'))
      setNotice('Copied')
    } catch {
      setNotice('Could not copy')
    }
  }

  /** Render each selected range separately. */
  function preview(latex: string, index: number) {
    return <MathPreview key={index} latex={latex} />
  }

  if (!selection) return null
  return createPortal(
    <div ref={menuRef} className="primitive-popup expression-selection-menu" role="dialog" aria-label="Selected expression" onPointerDown={keepSelection}>
      <div className="expression-selection-preview">{selection.latex.map(preview)}</div>
      <Button variant="quiet" onClick={copy}>
        <CopyIcon /> Copy
      </Button>
      {notice && <span role="status">{notice}</span>}
    </div>,
    document.body,
  )
}
