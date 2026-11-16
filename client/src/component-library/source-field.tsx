/**
 * Edit Markdown or LaTeX as literal source without expression shortcuts or rendered tokens. Mounted only during cell editing; contains text updates, focus, and height adjustment shared by both cell kinds.
 *
 * @file
 */
import { useLayoutEffect, useRef } from 'react'
import type { ChangeEvent, KeyboardEvent } from 'react'

/** Focus the active cell's source editor and preserve literal backslashes and line breaks. */
export function SourceField({ value, onChange, label, onFinish }: { value: string; onChange: (value: string) => void; label: string; onFinish?: () => void }) {
  const ref = useRef<HTMLTextAreaElement>(null)
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
  }
  useLayoutEffect(focusEditor, [])
  /** Report literal text without parsing or expanding commands. */
  function change(event: ChangeEvent<HTMLTextAreaElement>) {
    onChange(event.target.value)
  }
  /** Let standalone cells leave editing with Escape; notebook commands intercept it first. */
  function handleKey(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key !== 'Escape' || !onFinish) return
    event.preventDefault()
    onFinish()
  }
  return <textarea ref={ref} className="cell-source" aria-label={label} value={value} onChange={change} onKeyDown={handleKey} rows={1} spellCheck={false} />
}
