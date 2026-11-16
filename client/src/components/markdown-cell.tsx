/**
 * Edit Markdown source or display its rendered content inside one notebook cell. Contains local edit mode, keyboard completion, source sizing, and Markdown rendering with tables and inline or display mathematics.
 *
 * @file
 */

import { useId, useLayoutEffect, useRef, useState } from 'react'
import type { ChangeEvent, KeyboardEvent } from 'react'
import { Button } from '#/component-library/button.tsx'
import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import remarkMath from 'remark-math'
import rehypeKatex from 'rehype-katex'

/** Receive the cell's controlled Markdown source and report edits to the notebook without replacing its stable identity. */
interface MarkdownCellProps {
  cellId: string
  markdown: string
  onMarkdownChange: (cellId: string, markdown: string) => void
}

/** Keep only the editing mode local; store every source edit in the parent notebook and render that same source when editing finishes. */
export function MarkdownCell({ cellId, markdown, onMarkdownChange }: MarkdownCellProps) {
  const [isEditing, setIsEditing] = useState(!markdown.trim())
  const editorRef = useRef<HTMLTextAreaElement>(null)
  const previewRef = useRef<HTMLDivElement>(null)
  const hasEditedRef = useRef(false)
  const hintId = useId()

  /** Focus the active editing surface, returning keyboard focus to the rendered cell after finishing an edit. */
  function focusActiveSurface() {
    if (isEditing) {
      hasEditedRef.current = true
      editorRef.current?.focus()
    } else if (hasEditedRef.current) previewRef.current?.focus()
  }
  useLayoutEffect(focusActiveSurface, [isEditing])

  /** Grow or shrink the source field with its content so long notes do not introduce a nested editor scrollbar. */
  function resizeSource() {
    const editor = editorRef.current
    if (!editor) return
    editor.style.height = 'auto'
    editor.style.height = `${editor.scrollHeight}px`
  }
  useLayoutEffect(resizeSource, [markdown, isEditing])

  /** Begin editing the existing source without converting the rendered document back into Markdown. */
  function beginEditing() {
    setIsEditing(true)
  }

  /** Show the current source as rendered Markdown; edits already live in notebook state. */
  function finishEditing() {
    setIsEditing(false)
  }

  /** Report the full source after each text change, preserving ordinary textarea undo and selection. */
  function handleSourceChange(event: ChangeEvent<HTMLTextAreaElement>) {
    onMarkdownChange(cellId, event.target.value)
  }

  /** Finish editing with Command/Control-Enter or Escape while leaving composition, newlines, and ordinary text navigation to the textarea. */
  function handleSourceKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.nativeEvent.isComposing) return
    if (event.key === 'Escape' || (event.key === 'Enter' && (event.metaKey || event.ctrlKey))) {
      event.preventDefault()
      finishEditing()
    }
  }

  /** Enter edit mode from a focused rendered cell without intercepting links or other interactive descendants. */
  function handlePreviewKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget || event.key !== 'Enter') return
    event.preventDefault()
    beginEditing()
  }

  return (
    <section className={`markdown-cell${isEditing ? ' is-editing' : ''}`} aria-label="Markdown cell">
      <div className="markdown-toolbar">
        <span>{isEditing ? 'Editing Markdown' : 'Text & math'}</span>
        <Button onClick={isEditing ? finishEditing : beginEditing}>{isEditing ? 'Done' : 'Edit'}</Button>
      </div>
      {isEditing ? (
        <>
          <textarea
            ref={editorRef}
            className="markdown-source"
            aria-label="Markdown source"
            aria-describedby={hintId}
            value={markdown}
            onChange={handleSourceChange}
            onKeyDown={handleSourceKeyDown}
            placeholder={'## A heading or a thought\n\nExplain your reasoning. Use $x^2$ for inline math.'}
            spellCheck
            rows={5}
          />
          <p className="markdown-hint" id={hintId}>
            # heading · **bold** · $math$ <span>⌘ / Ctrl + Enter to finish</span>
          </p>
        </>
      ) : (
        <div ref={previewRef} className="markdown-rendered" tabIndex={0} aria-label="Rendered Markdown; press Enter to edit" onKeyDown={handlePreviewKeyDown}>
          {markdown.trim() ? (
            <Markdown remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[rehypeKatex]} skipHtml>
              {markdown}
            </Markdown>
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
