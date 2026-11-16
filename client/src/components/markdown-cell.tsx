/**
 * Edit Markdown source or display its rendered content inside one notebook cell. Contains local edit mode, keyboard completion, and Markdown rendering with tables and mathematics. Typing `$` inserts a MathLive expression that stays rendered while editing.
 *
 * @file
 */

import { useLayoutEffect, useRef, useState } from 'react'
import type { KeyboardEvent } from 'react'
import { MarkdownMathField } from '#/component-library/markdown-math-field.tsx'
import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import remarkMath from 'remark-math'
import rehypeKatex from 'rehype-katex'

/** Receive the cell's controlled Markdown source and report edits to the notebook without replacing its stable identity. `readOnly` shows the rendered note and hides editing. */
interface MarkdownCellProps {
  cellId: string
  markdown: string
  onMarkdownChange: (cellId: string, markdown: string) => void
  editing?: boolean
  onEditingChange?: (editing: boolean) => void
  readOnly?: boolean
}

/** Render stored Markdown, including its mathematics. The caller decides what an empty cell shows. */
function MarkdownDocument({ markdown }: { markdown: string }) {
  return (
    <Markdown remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[rehypeKatex]} skipHtml>
      {markdown}
    </Markdown>
  )
}

/** Keep only the editing mode local; store every source edit in the parent notebook and render that same source when editing finishes. A read-only cell never enters edit mode. */
export function MarkdownCell({ cellId, markdown, onMarkdownChange, editing, onEditingChange, readOnly = false }: MarkdownCellProps) {
  const [localEditing, setLocalEditing] = useState(!readOnly && !markdown.trim())
  const isEditing = editing ?? localEditing
  const setIsEditing = onEditingChange ?? setLocalEditing
  const editorRef = useRef<HTMLDivElement>(null)
  const previewRef = useRef<HTMLDivElement>(null)
  const hasEditedRef = useRef(false)

  /** Focus the active editing surface, returning keyboard focus to the rendered cell after finishing an edit. */
  function focusActiveSurface() {
    if (isEditing) {
      hasEditedRef.current = false
      editorRef.current?.focus()
    } else if (hasEditedRef.current) previewRef.current?.focus()
  }
  useLayoutEffect(focusActiveSurface, [isEditing])

  /** Begin editing the existing source without converting the rendered document back into Markdown. */
  function beginEditing() {
    setIsEditing(true)
  }

  /** Show the current source as rendered Markdown; edits already live in notebook state. */
  function finishEditing() {
    hasEditedRef.current = true
    setIsEditing(false)
  }

  /** Report the full source after each edit. Expressions are stored with `$` delimiters and shown rendered in the field. */
  function handleSourceChange(next: string) {
    onMarkdownChange(cellId, next)
  }

  /** Enter edit mode from a focused rendered cell without intercepting links or other interactive descendants. */
  function handlePreviewKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget || event.key !== 'Enter') return
    event.preventDefault()
    beginEditing()
  }

  /** Open the editor from a click on prose while leaving links and text selection usable. */
  function editProse(event: React.MouseEvent<HTMLDivElement>) {
    if (event.target instanceof Element && !event.target.closest('a,button') && !window.getSelection()?.toString()) beginEditing()
  }

  if (readOnly) {
    return (
      <section className="markdown-cell" aria-label="Markdown cell">
        <div className="markdown-rendered">{markdown.trim() ? <MarkdownDocument markdown={markdown} /> : <p className="markdown-empty">No note yet.</p>}</div>
      </section>
    )
  }

  return (
    <section className={`markdown-cell${isEditing ? ' is-editing' : ''}`} aria-label="Markdown cell">
      {isEditing ? (
        <>
          <MarkdownMathField fieldRef={editorRef} className="markdown-source" value={markdown} onChange={handleSourceChange} label="Markdown source" placeholder="Write a note…" onEscape={onEditingChange ? undefined : finishEditing} onCommandEnter={onEditingChange ? undefined : finishEditing} />
        </>
      ) : (
        <div ref={previewRef} onClick={editProse} className="markdown-rendered" tabIndex={0} aria-label="Rendered Markdown; press Enter to edit" onKeyDown={handlePreviewKeyDown}>
          {markdown.trim() ? (
            <MarkdownDocument markdown={markdown} />
          ) : (
            <button type="button" className="markdown-empty" onClick={beginEditing}>
              Write a note, a proof, or a question…
            </button>
          )}
        </div>
      )}
    </section>
  )
}
