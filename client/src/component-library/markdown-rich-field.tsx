/**
 * Edit rendered Markdown with Tiptap while storing Markdown source. Contains prose formatting, Markdown shortcuts, and inline/block math nodes that reuse Folio's visual editor and shared preview.
 *
 * @file
 */
import { useEffect, useRef, useState } from 'react'
import { EditorContent, NodeViewWrapper, ReactNodeViewRenderer, useEditor } from '@tiptap/react'
import type { NodeViewProps, Editor, JSONContent, MarkdownRendererHelpers, RenderContext } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import { Markdown } from '@tiptap/markdown'
import { InlineMath, BlockMath } from '@tiptap/extension-mathematics'
import { TaskList, TaskItem } from '@tiptap/extension-list'
import { TableKit } from '@tiptap/extension-table'
import Image from '@tiptap/extension-image'
import { LatexEditor } from '#/components/latex-editor'
import { MathPreview } from './math-preview'

/** Render math through the same preview and MathLive editor used by notebook cells. */
function MarkdownFormula({ node, updateAttributes, editor, getPos, deleteNode }: NodeViewProps) {
  const [editing, setEditing] = useState(!node.attrs.latex)
  const inline = node.type.name === 'inlineMath'
  const latex = String(node.attrs.latex ?? '')
  /** Keep edits in this node's LaTeX attribute; Markdown serialization retains its dollar delimiters. */
  function change(value: string) {
    updateAttributes({ latex: value })
  }
  /** Return to the prose immediately after this formula. */
  function finish() {
    setEditing(false)
    const position = getPos()
    if (position !== undefined)
      editor
        .chain()
        .focus()
        .setTextSelection(position + node.nodeSize)
        .run()
  }
  /** Remove a newly inserted empty expression, or leave an existing expression intact. */
  function cancel() {
    if (!latex.trim()) {
      deleteNode()
      editor.commands.focus()
      return
    }
    finish()
  }
  /** Activate this expression without changing its source. */
  function begin() {
    setEditing(true)
  }
  return (
    <NodeViewWrapper as={inline ? 'span' : 'div'} className={inline ? 'markdown-rich-math' : 'markdown-rich-math is-display'} contentEditable={false}>
      {editing ? (
        <LatexEditor initialLatex={latex} onLatexChange={change} layout="inline" startEditing onCommit={finish} onCancel={cancel} label="Markdown expression" />
      ) : (
        <button type="button" onClick={begin} aria-label="Edit expression">
          <MathPreview latex={latex} display={!inline} />
        </button>
      )}
    </NodeViewWrapper>
  )
}

/** Give inline and block formula nodes the same React view. Their Markdown parsing and serialization stay in the official math extensions. */
function formulaView() {
  return ReactNodeViewRenderer(MarkdownFormula)
}
/** Omit unfinished formulas and separate adjacent inline formulas so their dollar delimiters remain unambiguous. */
function inlineMarkdown(node: JSONContent, _helpers: MarkdownRendererHelpers, context: RenderContext) {
  const separator = context.previousNode?.type === 'inlineMath' ? ' ' : ''
  return node.attrs?.latex ? `${separator}$${String(node.attrs.latex)}$` : ''
}
/** Keep displayed formulas on their own Markdown lines and omit an unfinished empty formula. */
function blockMarkdown(node: JSONContent) {
  return node.attrs?.latex ? `$$\n${String(node.attrs.latex)}\n$$` : ''
}
export const markdownExtensions = [StarterKit, Markdown, InlineMath.extend({ addNodeView: formulaView, renderMarkdown: inlineMarkdown }), BlockMath.extend({ addNodeView: formulaView, renderMarkdown: blockMarkdown }), TaskList, TaskItem.configure({ nested: true }), TableKit, Image]

/** Edit rendered prose without replacing the document on each keystroke. Source updates from commands are applied only when they differ from the last emitted Markdown. */
export function MarkdownRichField({ value, onChange, onFinish }: { value: string; onChange: (value: string) => void; onFinish?: () => void }) {
  const source = useRef(value)
  const editor: Editor | null = useEditor({
    extensions: markdownExtensions,
    content: value,
    contentType: 'markdown',
    immediatelyRender: false,
    autofocus: 'start',
    /** Publish Markdown after document edits, leaving selection-only transactions local. */
    onUpdate({ editor: current }: { editor: Editor }) {
      source.current = current.getMarkdown()
      onChange(source.current)
    },
    editorProps: {
      /** Preserve Markdown syntax and math delimiters when formatted content is copied. */
      clipboardTextSerializer(slice): string {
        return editor?.markdown?.serialize({ type: 'doc', content: slice.content.toJSON() as JSONContent[] }) ?? slice.content.textBetween(0, slice.content.size, '\n')
      },
      /** Parse a plain-text Markdown paste while leaving rich HTML pastes to the editor. */
      handlePaste(_view, event) {
        const latex = event.clipboardData?.getData('application/x-latex')
        if (editor && latex) return editor.commands.insertInlineMath({ latex })
        const text = event.clipboardData?.getData('text/plain')
        if (!editor || !text || event.clipboardData?.getData('text/html')) return false
        editor.commands.insertContent(text, { contentType: 'markdown' })
        return true
      },
      attributes: { class: 'markdown-rendered markdown-rich-editor', role: 'textbox', 'aria-label': 'Markdown editor', 'aria-multiline': 'true' },
      /** Open visual math on dollar input, keeping ordinary Markdown formatting shortcuts inside Tiptap. */
      handleKeyDown(_view, event) {
        if (onFinish && (event.key === 'Escape' || (event.key === 'Enter' && (event.metaKey || event.ctrlKey)))) {
          onFinish()
          return true
        }
        if (event.key !== '$' || event.isComposing || event.metaKey || event.ctrlKey || event.altKey) return false
        if (!editor || editor.isActive('codeBlock') || editor.isActive('code')) return false
        editor.commands.insertContent({ type: 'inlineMath', attrs: { latex: '' } })
        return true
      },
    },
  })
  /** Apply externally replaced content without rewriting the document after its own edits. */
  function syncSource() {
    if (!editor || value === source.current) return
    source.current = value
    editor.commands.setContent(value, { contentType: 'markdown', emitUpdate: false })
  }
  useEffect(syncSource, [editor, value])
  return <EditorContent editor={editor} />
}
