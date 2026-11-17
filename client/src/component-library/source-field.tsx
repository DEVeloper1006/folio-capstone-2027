/**
 * Edit Markdown or LaTeX as literal source without expression shortcuts or rendered tokens. Mounted only during cell editing; contains text updates, focus, and height adjustment shared by both cell kinds.
 *
 * @file
 */
import { useLayoutEffect, useRef, useState } from 'react'
import type { ChangeEvent, KeyboardEvent } from 'react'

import { useCellAutocomplete } from '#/notebook/use-cell-autocomplete'

/** Focus the active cell's source editor and preserve literal backslashes and line breaks. */
export function SourceField({ value, previous, onChange, label, onFinish }: { previous?: string; value: string; onChange: (value: string) => void; label: string; onFinish?: () => void }) {
  const ref = useRef<HTMLTextAreaElement>(null)
  const [atEnd, setAtEnd] = useState(false)
  const suffix = useCellAutocomplete(previous, value, atEnd)
  /** Offer append-only suggestions at a collapsed end caret. */
  function trackCaret() {
    const field = ref.current
    setAtEnd(!!field && document.activeElement === field && field.selectionStart === field.value.length && field.selectionEnd === field.value.length)
  }
  /** Grow with the source so every line remains visible. */
  function resize() {
    if (!ref.current) return
    ref.current.style.height = 'auto'
    ref.current.style.height = `${ref.current.scrollHeight}px`
  }
  useLayoutEffect(resize, [value])
  /** Focus once on entry without moving the caret after each edit. */
  function focusEditor() {
    ref.current?.focus()
    trackCaret()
  }
  useLayoutEffect(focusEditor, [])
  /** Report literal text without parsing or expanding commands. */
  function change(event: ChangeEvent<HTMLTextAreaElement>) {
    onChange(event.target.value)
  }
  /** Let standalone cells leave editing with Escape; notebook commands intercept it first. */
  function handleKey(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Tab' && !event.shiftKey && suffix && event.currentTarget.selectionStart === value.length) {
      event.preventDefault()
      onChange(value + suffix)
      return
    }
    if (event.key !== 'Escape' || !onFinish) return
    event.preventDefault()
    onFinish()
  }
  return (
    <div className="source-stack">
      {suffix && (
        <div aria-hidden="true" className="cell-source source-ghost">
          <span>{value}</span>
          {suffix}
        </div>
      )}
      <textarea onSelect={trackCaret} onBlur={trackCaret} onFocus={trackCaret} ref={ref} className="cell-source" aria-label={label} value={value} onChange={change} onKeyDown={handleKey} rows={1} spellCheck={false} />
    </div>
  )
}
