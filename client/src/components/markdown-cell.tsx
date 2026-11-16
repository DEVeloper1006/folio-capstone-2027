/**
 * Edit Markdown as rendered prose or literal source inside one notebook cell. Contains the page-mode switch, local edit/preview state, Markdown rendering, and LaTeX-preserving copy for rendered mathematics. Typing `$` inserts a MathLive expression that stays rendered while editing.
 *
 * @file
 */

import { useLayoutEffect, useRef, useState } from 'react'
import type { ClipboardEvent, KeyboardEvent } from 'react'
import { MarkdownRichField } from '#/component-library/markdown-rich-field'
import { SourceField } from '#/component-library/source-field'
import type { CellEditorMode } from '#/notebook/page'
import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import remarkMath from 'remark-math'
import rehypeKatex from 'rehype-katex'
import { previewMacros } from '#/editor/mathlive/mathfield-macros'

/** Receive the cell's controlled Markdown source and report edits to the notebook without replacing its stable identity. `readOnly` shows the rendered note and hides editing. */
interface MarkdownCellProps {
  cellId: string
  editorMode?: CellEditorMode
  markdown: string
  onMarkdownChange: (cellId: string, markdown: string) => void
  editing?: boolean
  onEditingChange?: (editing: boolean) => void
  readOnly?: boolean
}

/** Render stored Markdown, including its mathematics. The caller decides what an empty cell shows. */
function MarkdownDocument({ markdown }: { markdown: string }) {
  return (
    <Markdown remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[[rehypeKatex, { macros: { ...previewMacros } }]]} skipHtml>
      {markdown}
    </Markdown>
  )
}

/** Find the complete rendered formula containing a selection endpoint. */
function containingFormula(node: Node) {
  return (node instanceof Element ? node : node.parentElement)?.closest('.katex')
}

/** Copy preview mathematics from its original LaTeX annotation. Partial formula selections copy the whole expression, as KaTeX's copy-tex extension does. */
function copyRenderedMath(event: ClipboardEvent<HTMLDivElement>) {
  const selection = window.getSelection()
  if (!selection || selection.isCollapsed || selection.rangeCount !== 1) return
  const range = selection.getRangeAt(0).cloneRange()
  const preview = event.currentTarget
  if (!preview.contains(range.startContainer) || !preview.contains(range.endContainer)) return
  const start = containingFormula(range.startContainer)
  const end = containingFormula(range.endContainer)
  if (start) range.setStartBefore(start)
  if (end) range.setEndAfter(end)
  const fragment = range.cloneContents()
  const formulas = Array.from(fragment.querySelectorAll('.katex'))
  if (!formulas.length) return
  const copy = document.createElement('div')
  copy.append(fragment)
  event.clipboardData.setData('text/html', copy.innerHTML)
  let singleLatex: string | undefined
  for (const formula of formulas) {
    const latex = formula.querySelector('annotation[encoding="application/x-tex"]')?.textContent
    if (latex === undefined) return
    singleLatex = latex
    const delimiter = formula.closest('.katex-display') ? '$$' : '$'
    formula.replaceWith(document.createTextNode(delimiter + latex + delimiter))
  }
  // Preserve line breaks between selected paragraphs and lists in plain-text pastes.
  for (const block of copy.querySelectorAll('p,div,li,h1,h2,h3,h4,h5,h6,blockquote,pre')) {
    block.prepend(document.createTextNode('\n'))
    block.append(document.createTextNode('\n'))
  }
  for (const br of copy.querySelectorAll('br')) br.replaceWith(document.createTextNode('\n'))
  const text = copy.textContent.trim()
  const formulaOnly = formulas.length === 1 && (text === '$' + singleLatex + '$' || text === '$$' + singleLatex + '$$')
  event.clipboardData.setData('text/plain', formulaOnly ? (singleLatex ?? '') : text)
  if (formulaOnly) event.clipboardData.setData('application/x-latex', singleLatex ?? '')
  event.preventDefault()
}

/** Keep only the editing mode local; store every source edit in the parent notebook and render that same source when editing finishes. A read-only cell never enters edit mode. */
export function MarkdownCell({ editorMode = 'rich', cellId, markdown, onMarkdownChange, editing, onEditingChange, readOnly = false }: MarkdownCellProps) {
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

  if (editorMode === 'source' && isEditing && !readOnly) return <SourceField value={markdown} onChange={handleSourceChange} label="Markdown source" onFinish={onEditingChange ? undefined : finishEditing} />

  if (readOnly) {
    return (
      <section className="markdown-cell" aria-label="Markdown cell">
        <div className="markdown-rendered" onCopy={copyRenderedMath}>
          {markdown.trim() ? <MarkdownDocument markdown={markdown} /> : <p className="markdown-empty">No note yet.</p>}
        </div>
      </section>
    )
  }

  return (
    <section className={`markdown-cell${isEditing ? ' is-editing' : ''}`} aria-label="Markdown cell">
      {isEditing ? (
        <>
          <MarkdownRichField value={markdown} onChange={handleSourceChange} onFinish={onEditingChange ? undefined : finishEditing} />
        </>
      ) : (
        <div onCopy={copyRenderedMath} ref={previewRef} onClick={editProse} className="markdown-rendered" tabIndex={0} aria-label="Rendered Markdown; press Enter to edit" onKeyDown={handlePreviewKeyDown}>
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
