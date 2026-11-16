/**
 * Edit Markdown prose with mathematics inserted as expressions, not typed as `$...$` source. Typing `$` opens the same MathLive field a notebook cell uses. Arrow keys move into that formula and back out to the sentence. Enter stores it as rendered math. The stored string still uses `$` delimiters
 * so existing Markdown renderers can typeset it.
 *
 * @file
 */

import { memo, useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { ClipboardEvent, FormEvent, KeyboardEvent, MouseEvent, RefObject } from 'react'
import { createPortal } from 'react-dom'
import type { MathfieldElement } from 'mathlive'
import { preloadMathLive } from '#/editor/index.ts'
import { LatexEditor, renderLatexMarkup } from '#/components/latex-editor.tsx'

/** One stretch of prose, or one expression, in reading order. */
type MathRun = { kind: 'text'; text: string } | { kind: 'math'; latex: string; display: boolean }

/** An expression being typed. The anchor sits in the prose where the rendered math will land. */
interface ExpressionSession {
  latex: string
  display: boolean
  anchor: HTMLSpanElement
}

/** Describe the controlled Markdown string and the keys the surrounding editor wants to keep. */
interface MarkdownMathFieldProps {
  value: string
  onChange: (value: string) => void
  label: string
  placeholder?: string
  className?: string
  describedBy?: string
  fieldRef?: RefObject<HTMLDivElement | null>
  /** Enter sends the field. Shift+Enter still inserts a newline. */
  submitOnEnter?: boolean
  onSubmit?: () => void
  /** Escape while the expression inserter is closed. */
  onEscape?: () => void
  /** Command/Control-Enter, used by a Markdown cell to finish editing. */
  onCommandEnter?: () => void
}

/** Stable listeners for the contenteditable surface. The surface itself does not re-render while someone is typing. */
interface FieldHandlers {
  assignEditor: (node: HTMLDivElement | null) => void
  handleInput: (event: FormEvent<HTMLDivElement>) => void
  handleKeyDown: (event: KeyboardEvent<HTMLDivElement>) => void
  handleClick: (event: MouseEvent<HTMLDivElement>) => void
  handlePaste: (event: ClipboardEvent<HTMLDivElement>) => void
}

/** Split a stored Markdown string into prose and `$...$` or `$$...$$` expressions. Unclosed dollars stay as text. */
function parseMathSource(source: string): readonly MathRun[] {
  const runs: MathRun[] = []
  let text = ''
  let index = 0

  /** Flush the prose accumulated since the previous expression. */
  function pushText() {
    if (text.length === 0) return
    runs.push({ kind: 'text', text })
    text = ''
  }

  while (index < source.length) {
    const display = source.startsWith('$$', index)
    const opener = display ? '$$' : source[index] === '$' ? '$' : ''
    if (opener.length > 0) {
      const end = source.indexOf(opener, index + opener.length)
      const latex = end === -1 ? null : source.slice(index + opener.length, end)
      if (latex !== null && !latex.includes('\n')) {
        pushText()
        runs.push({ kind: 'math', latex, display })
        index = end + opener.length
        continue
      }
    }
    text += source[index]
    index += 1
  }
  pushText()
  return runs
}

/** Build the non-editable math atom shown in the sentence after an expression is inserted. */
function createMathChip(latex: string, display: boolean) {
  const chip = document.createElement('span')
  chip.className = 'markdown-math-chip'
  chip.contentEditable = 'false'
  chip.dataset.latex = latex
  chip.dataset.display = display ? 'true' : 'false'
  chip.setAttribute('role', 'button')
  chip.tabIndex = -1
  chip.setAttribute('aria-label', `Edit expression ${latex}`)
  chip.innerHTML = renderLatexMarkup(latex, display)
  return chip
}

/** Read the field back into Markdown, turning each chip into `$...$` or `$$...$$` and each line break into a newline. */
function serializeNode(node: Node): string {
  if (node.nodeType === Node.TEXT_NODE) return (node.textContent ?? '').replaceAll('\u200B', '')
  if (!(node instanceof HTMLElement)) return ''
  if (node.dataset.expressionAnchor === 'true') {
    if (node.dataset.latex === undefined) return ''
    const latex = node.dataset.latex
    return node.dataset.display === 'true' ? `$$${latex}$$` : `$${latex}$`
  }
  if (node.dataset.latex !== undefined) {
    const latex = node.dataset.latex
    return node.dataset.display === 'true' ? `$$${latex}$$` : `$${latex}$`
  }
  if (node.tagName === 'BR') return '\n'
  let inner = ''
  for (const child of node.childNodes) inner += serializeNode(child)
  if (node.tagName === 'DIV' || node.tagName === 'P') return `\n${inner}`
  return inner
}

/** Read a whole field, including lines the browser wrapped in divs. */
function serializeField(editor: HTMLElement) {
  let value = ''
  for (const child of editor.childNodes) value += serializeNode(child)
  return value.replace(/^\n/, '')
}

/** Replace the field's DOM with prose text nodes, line breaks, and math chips for one stored Markdown string. */
function writeField(editor: HTMLElement, source: string) {
  const fragment = document.createDocumentFragment()
  for (const run of parseMathSource(source)) {
    if (run.kind === 'text') appendText(fragment, run.text)
    else fragment.append(createMathChip(run.latex, run.display))
  }
  const last = fragment.lastChild
  if (last !== null && last.nodeType !== Node.TEXT_NODE) fragment.append(document.createTextNode('\u200B'))
  editor.replaceChildren(fragment)
}

/** Add prose, turning newline characters into `<br>` elements so the field keeps paragraph breaks. */
function appendText(parent: DocumentFragment, text: string) {
  const lines = text.split('\n')
  for (let index = 0; index < lines.length; index += 1) {
    if (index > 0) parent.append(document.createElement('br'))
    if (lines[index].length > 0) parent.append(document.createTextNode(lines[index]))
  }
}

/** Place the caret immediately after a node and focus the field that contains it. */
function placeCaretAfter(node: Node) {
  placeCaretBeside(node, 'after')
}

/** Place the caret immediately before a node and focus the field that contains it. */
function placeCaretBefore(node: Node) {
  placeCaretBeside(node, 'before')
}

/** Place the caret on one side of a node and focus the field that contains it. */
function placeCaretBeside(node: Node, edge: 'before' | 'after') {
  const editor = node.parentElement
  const selection = window.getSelection()
  if (editor === null || selection === null) return
  const range = document.createRange()
  if (edge === 'before') range.setStartBefore(node)
  else range.setStartAfter(node)
  range.collapse(true)
  selection.removeAllRanges()
  selection.addRange(range)
  if (editor instanceof HTMLElement) editor.focus()
}

/** Return true when a text node holds only the zero-width space used to park the caret. */
function isSpacerText(node: Node) {
  return node.nodeType === Node.TEXT_NODE && (node.textContent ?? '').replaceAll('\u200B', '').length === 0
}

/** Skip caret spacers and return the next real node in that direction. */
function neighborSkippingSpacers(node: Node | null, direction: 'next' | 'previous') {
  let current = node
  while (current !== null && isSpacerText(current)) current = direction === 'next' ? current.nextSibling : current.previousSibling
  return current
}

/** Return the expression sitting against a collapsed caret, or null when prose is still between them. */
function expressionBesideCaret(editor: HTMLElement, side: 'before' | 'after') {
  const selection = window.getSelection()
  if (selection === null || !selection.isCollapsed || selection.rangeCount === 0) return null
  const range = selection.getRangeAt(0)
  if (!editor.contains(range.startContainer)) return null
  const candidate = side === 'after' ? nodeAfterCaret(range) : nodeBeforeCaret(range)
  if (!(candidate instanceof HTMLElement)) return null
  if (!candidate.classList.contains('markdown-math-chip') && !candidate.classList.contains('markdown-expression-anchor')) return null
  return candidate
}

/** Return the node that follows the caret when no real characters remain in the current text. */
function nodeAfterCaret(range: Range) {
  const container = range.startContainer
  if (container.nodeType === Node.TEXT_NODE) {
    const text = container.textContent ?? ''
    if (text.slice(range.startOffset).replaceAll('\u200B', '').length > 0) return null
    return neighborSkippingSpacers(container.nextSibling, 'next')
  }
  return neighborSkippingSpacers(container.childNodes[range.startOffset] ?? null, 'next')
}

/** Return the node that precedes the caret when no real characters remain before it. */
function nodeBeforeCaret(range: Range) {
  const container = range.startContainer
  if (container.nodeType === Node.TEXT_NODE) {
    const text = container.textContent ?? ''
    if (text.slice(0, range.startOffset).replaceAll('\u200B', '').length > 0) return null
    return neighborSkippingSpacers(container.previousSibling, 'previous')
  }
  return neighborSkippingSpacers(container.childNodes[range.startOffset - 1] ?? null, 'previous')
}

/** Move the caret to one edge of an open inline formula. */
function focusInlineMathfield(anchor: HTMLElement, edge: 'start' | 'end') {
  const mathfield = anchor.querySelector('math-field')
  if (!(mathfield instanceof HTMLElement) || mathfield.tagName !== 'MATH-FIELD') return
  const field = mathfield as MathfieldElement
  field.focus()
  field.position = edge === 'start' ? 0 : field.lastOffset
}

/** Move the caret to the end after a paste that was rewritten into chips. */
function placeCaretAtEnd(editor: HTMLElement) {
  const selection = window.getSelection()
  if (selection === null) return
  const range = document.createRange()
  range.selectNodeContents(editor)
  range.collapse(false)
  selection.removeAllRanges()
  selection.addRange(range)
  editor.focus()
}

/** Return the character immediately before a collapsed caret, or an empty string when the caret is not in a text node. */
function characterBeforeCaret() {
  const selection = window.getSelection()
  if (selection === null || !selection.isCollapsed || selection.rangeCount === 0) return ''
  const range = selection.getRangeAt(0)
  if (range.startContainer.nodeType !== Node.TEXT_NODE || range.startOffset === 0) return ''
  return range.startContainer.textContent?.charAt(range.startOffset - 1) ?? ''
}

/** Delete the single character before the caret. Used when a `$` is already in the sentence and another `$` opens an expression. */
function deleteCharacterBeforeCaret() {
  const selection = window.getSelection()
  if (selection === null || selection.rangeCount === 0) return
  const range = selection.getRangeAt(0)
  if (range.startContainer.nodeType !== Node.TEXT_NODE || range.startOffset === 0) return
  range.setStart(range.startContainer, range.startOffset - 1)
  range.deleteContents()
}

/** Insert a `<br>` at the caret, then a zero-width space so the new line is visible and the caret can sit on it. */
function insertLineBreak() {
  const selection = window.getSelection()
  if (selection === null || selection.rangeCount === 0) return
  const range = selection.getRangeAt(0)
  if (!range.collapsed) range.deleteContents()
  const lineBreak = document.createElement('br')
  range.insertNode(lineBreak)
  const spacer = document.createTextNode('\u200B')
  lineBreak.after(spacer)
  const next = document.createRange()
  next.setStart(spacer, 1)
  next.collapse(true)
  selection.removeAllRanges()
  selection.addRange(next)
}

/** Hold an editor node before the field has mounted. */
function ignoreEditorNode(_node: HTMLDivElement | null) {}

/** Ignore a prose edit before the field installs its listener. */
function ignoreFieldInput(_event: FormEvent<HTMLDivElement>) {}

/** Ignore a key before the field installs its listener. */
function ignoreFieldKey(_event: KeyboardEvent<HTMLDivElement>) {}

/** Ignore a click before the field installs its listener. */
function ignoreFieldClick(_event: MouseEvent<HTMLDivElement>) {}

/** Ignore a paste before the field installs its listener. */
function ignoreFieldPaste(_event: ClipboardEvent<HTMLDivElement>) {}

/** Insert plain text at the caret without interpreting it as HTML. */
function insertTextAtCaret(text: string) {
  const selection = window.getSelection()
  if (selection === null || selection.rangeCount === 0) return
  const range = selection.getRangeAt(0)
  range.deleteContents()
  const node = document.createTextNode(text)
  range.insertNode(node)
  range.setStartAfter(node)
  range.collapse(true)
  selection.removeAllRanges()
  selection.addRange(range)
}

/** Render the contenteditable surface. It stays mounted so typing does not rebuild the sentence and move the caret. */
function FieldBody({ className, handlers }: { className: string; handlers: FieldHandlers }) {
  return <div ref={handlers.assignEditor} className={className} contentEditable role="textbox" aria-multiline="true" spellCheck suppressContentEditableWarning onInput={handlers.handleInput} onKeyDown={handlers.handleKeyDown} onClick={handlers.handleClick} onPaste={handlers.handlePaste} />
}

const StableFieldBody = memo(FieldBody)

/** Ignore live MathLive edits. The markdown string changes when Enter commits the formula, not on each keystroke. */
function ignoreLatexChange(_latex: string) {}

/** Edit one formula with the same MathLive field a notebook cell uses. Enter inserts it into the sentence. Left or Right at its edge returns to the surrounding text. Escape removes a new formula or restores an existing one. */
function ExpressionInserter({ initialLatex, caretEdge, onCommit, onCancel, onBoundary }: { initialLatex: string; caretEdge: 'start' | 'end'; onCommit: (latex: string) => void; onCancel: () => void; onBoundary: (edge: 'start' | 'end', latex: string) => void }) {
  /** Insert a non-empty formula, or remove an empty one. */
  function commitLatex(latex: string) {
    if (latex.trim().length === 0) onCancel()
    else onCommit(latex.trim())
  }

  return <LatexEditor initialLatex={initialLatex} onLatexChange={ignoreLatexChange} label="LaTeX expression" layout="inline" startEditing caretEdge={caretEdge} onCommit={commitLatex} onCancel={onCancel} onBoundary={onBoundary} />
}

/** Edit Markdown where mathematics is inserted with `$` and then shown rendered. Prose stays text. The `value` string is what gets stored and sent. */
export function MarkdownMathField({ value, onChange, label, placeholder, className, describedBy, fieldRef, submitOnEnter = false, onSubmit, onEscape, onCommandEnter }: MarkdownMathFieldProps) {
  useEffect(preloadMathLive, [])
  const editorRef = useRef<HTMLDivElement | null>(null)
  const skipSyncRef = useRef(false)
  const fieldRefLatest = useRef(fieldRef)
  fieldRefLatest.current = fieldRef
  const [expression, setExpression] = useState<ExpressionSession | null>(null)
  const caretEdgeRef = useRef<'start' | 'end'>('start')
  const fieldClass = className === undefined ? 'markdown-math-field' : `markdown-math-field ${className}`
  const handlersRef = useRef<FieldHandlers>({
    assignEditor: ignoreEditorNode,
    handleInput: ignoreFieldInput,
    handleKeyDown: ignoreFieldKey,
    handleClick: ignoreFieldClick,
    handlePaste: ignoreFieldPaste,
  })

  const stableHandlers = useRef<FieldHandlers | null>(null)
  if (stableHandlers.current === null) {
    stableHandlers.current = {
      /** Keep the mounted field node, and the optional ref the parent uses to focus it. */
      assignEditor(node) {
        editorRef.current = node
        const external = fieldRefLatest.current
        if (external) external.current = node
      },
      /** Ignore edits that belong to the expression input, and publish prose edits. */
      handleInput(event) {
        handlersRef.current.handleInput(event)
      },
      /** Open an expression on `$`, and forward Enter and Escape to the surrounding editor. */
      handleKeyDown(event) {
        handlersRef.current.handleKeyDown(event)
      },
      /** Reopen a rendered expression when its chip is clicked. */
      handleClick(event) {
        handlersRef.current.handleClick(event)
      },
      /** Paste plain text, turning any `$...$` or `$$...$$` in it into expressions. */
      handlePaste(event) {
        handlersRef.current.handlePaste(event)
      },
    }
  }

  /** Publish a stored Markdown string without writing it back into the field and moving the caret. */
  function publish(next: string) {
    if (next === value) return
    skipSyncRef.current = true
    onChange(next)
  }

  /** Replace the field when the stored string changed outside this component, such as after a send clears it. Leave the DOM alone while an expression is open and the prose still matches. */
  function syncFieldFromValue() {
    const editor = editorRef.current
    if (editor === null) return
    if (skipSyncRef.current) {
      skipSyncRef.current = false
      return
    }
    if (serializeField(editor) === value) return
    writeField(editor, value)
    if (expression !== null) setExpression(null)
  }
  useLayoutEffect(syncFieldFromValue, [value, expression])

  /** Keep the accessible name and placeholder on the mounted field. */
  function syncFieldLabels() {
    const editor = editorRef.current
    if (editor === null) return
    editor.setAttribute('aria-label', label)
    if (describedBy === undefined) editor.removeAttribute('aria-describedby')
    else editor.setAttribute('aria-describedby', describedBy)
    if (placeholder === undefined) delete editor.dataset.placeholder
    else editor.dataset.placeholder = placeholder
  }
  useLayoutEffect(syncFieldLabels, [label, placeholder, describedBy])

  /** Store the current prose after a keystroke. Typing inside the expression input does not change the stored sentence. */
  function handleInput(event: FormEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget) return
    publish(serializeField(event.currentTarget))
  }

  /** Open an expression when `$` is typed, adding the closing `$` on commit. Insert a newline, or hand Enter and Escape to the parent. */
  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget || event.nativeEvent.isComposing) return
    if ((event.key === 'ArrowLeft' || event.key === 'ArrowRight') && !event.shiftKey && !event.altKey && !event.metaKey && !event.ctrlKey) {
      const side = event.key === 'ArrowRight' ? 'after' : 'before'
      const neighbor = expressionBesideCaret(event.currentTarget, side)
      if (neighbor !== null) {
        event.preventDefault()
        const caretEdge = event.key === 'ArrowRight' ? 'start' : 'end'
        if (neighbor.classList.contains('markdown-expression-anchor')) focusInlineMathfield(neighbor, caretEdge)
        else enterChip(neighbor, caretEdge)
        return
      }
    }
    if (event.key === '$') {
      event.preventDefault()
      if (characterBeforeCaret() === '$') deleteCharacterBeforeCaret()
      openExpression('', false)
      return
    }
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey) && onCommandEnter !== undefined) {
      event.preventDefault()
      onCommandEnter()
      return
    }
    if (event.key === 'Enter') {
      event.preventDefault()
      if (event.shiftKey || !submitOnEnter) {
        insertLineBreak()
        const editor = editorRef.current
        if (editor !== null) publish(serializeField(editor))
        return
      }
      if (onSubmit !== undefined) onSubmit()
      return
    }
    if (event.key === 'Escape' && onEscape !== undefined) {
      event.preventDefault()
      onEscape()
    }
  }

  /** Turn a clicked math chip back into an expression at the same place in the sentence. */
  function handleClick(event: MouseEvent<HTMLDivElement>) {
    if (!(event.target instanceof Element)) return
    const chip = event.target.closest('.markdown-math-chip')
    if (!(chip instanceof HTMLElement) || chip.dataset.latex === undefined || expression !== null) return
    event.preventDefault()
    const latex = chip.dataset.latex
    const display = chip.dataset.display === 'true'
    replaceChipWithExpression(chip, latex, display, 'start')
  }

  /** Replace a rendered formula with the MathLive field and put the caret at the requested edge. */
  function enterChip(chip: HTMLElement, caretEdge: 'start' | 'end') {
    if (chip.dataset.latex === undefined || expression !== null) return
    replaceChipWithExpression(chip, chip.dataset.latex, chip.dataset.display === 'true', caretEdge)
  }

  /** Swap a chip for an editing anchor without changing the stored sentence until the formula is committed. */
  function replaceChipWithExpression(chip: HTMLElement, latex: string, display: boolean, caretEdge: 'start' | 'end') {
    caretEdgeRef.current = caretEdge
    const anchor = createAnchor(latex, display)
    chip.replaceWith(anchor)
    setExpression({ latex, display, anchor })
  }

  /** Paste text at the caret. Delimited math in the paste becomes expressions instead of remaining as source. */
  function handlePaste(event: ClipboardEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget) return
    event.preventDefault()
    const editor = editorRef.current
    if (editor === null) return
    insertTextAtCaret(event.clipboardData.getData('text/plain'))
    const serialized = serializeField(editor)
    if (serialized.includes('$')) {
      writeField(editor, serialized)
      placeCaretAtEnd(editor)
    }
    publish(serializeField(editor))
  }

  /** Insert the expression anchor at the caret and drop the `$` that opened it from the stored sentence. */
  function openExpression(latex: string, display: boolean) {
    const editor = editorRef.current
    const selection = window.getSelection()
    if (editor === null || selection === null || selection.rangeCount === 0 || expression !== null) return
    const range = selection.getRangeAt(0)
    if (!editor.contains(range.startContainer)) return
    range.deleteContents()
    caretEdgeRef.current = 'start'
    const anchor = createAnchor()
    range.insertNode(anchor)
    setExpression({ latex, display, anchor })
    publish(serializeField(editor))
  }

  /** Replace the open expression with a rendered chip and store the sentence. Enter leaves the caret after it; an arrow leaves the caret on the side that was pressed. */
  function commitExpression(latex: string, edge: 'before' | 'after' = 'after') {
    if (expression === null) return
    const chip = createMathChip(latex, expression.display)
    expression.anchor.replaceWith(chip)
    if (edge === 'before') placeCaretBefore(chip)
    else placeCaretAfter(chip)
    const editor = editorRef.current
    setExpression(null)
    if (editor !== null) publish(serializeField(editor))
  }

  /** Save the formula and step out of it. An empty formula is removed, including one that used to have content. */
  function leaveExpression(edge: 'start' | 'end', latex: string) {
    if (expression === null) return
    const trimmed = latex.trim()
    if (trimmed.length === 0) {
      const spacer = document.createTextNode('')
      expression.anchor.replaceWith(spacer)
      placeCaretAfter(spacer)
      const editor = editorRef.current
      setExpression(null)
      if (editor !== null) publish(serializeField(editor))
      return
    }
    commitExpression(trimmed, edge === 'start' ? 'before' : 'after')
  }

  /** Remove a new expression, or restore the chip when an existing expression was opened for editing. */
  function cancelExpression() {
    if (expression === null) return
    const { anchor } = expression
    if (anchor.dataset.latex !== undefined) {
      const chip = createMathChip(anchor.dataset.latex, anchor.dataset.display === 'true')
      anchor.replaceWith(chip)
      placeCaretAfter(chip)
    } else {
      const spacer = document.createTextNode('')
      anchor.replaceWith(spacer)
      placeCaretAfter(spacer)
    }
    setExpression(null)
    const editor = editorRef.current
    if (editor !== null) publish(serializeField(editor))
  }

  /** Return the listeners created for the mounted field. */
  function mountedHandlers() {
    const handlers = stableHandlers.current
    if (handlers === null) throw new Error('Markdown field handlers were not created.')
    return handlers
  }

  const handlers = mountedHandlers()
  handlersRef.current = { assignEditor: handlers.assignEditor, handleInput, handleKeyDown, handleClick, handlePaste }

  return (
    <>
      <StableFieldBody className={fieldClass} handlers={handlers} />
      {expression === null ? null : createPortal(<ExpressionInserter initialLatex={expression.latex} caretEdge={caretEdgeRef.current} onCommit={commitExpression} onCancel={cancelExpression} onBoundary={leaveExpression} />, expression.anchor)}
    </>
  )
}

/** Create the inline slot an expression editor is portaled into. An existing expression keeps its LaTeX on the slot so the stored sentence does not change until Enter. */
function createAnchor(latex?: string, display = false) {
  const anchor = document.createElement('span')
  anchor.className = 'markdown-expression-anchor'
  anchor.contentEditable = 'false'
  anchor.dataset.expressionAnchor = 'true'
  if (latex !== undefined) {
    anchor.dataset.latex = latex
    anchor.dataset.display = display ? 'true' : 'false'
  }
  return anchor
}
