/**
 * Render inline and display mathematics inside chat messages, context chips, selectable formulas, and agent tool cards.
 *
 * @file
 */

import katex from 'katex'
import Markdown from 'react-markdown'
import rehypeKatex from 'rehype-katex'
import remarkGfm from 'remark-gfm'
import remarkMath from 'remark-math'

/** Describe a standalone LaTeX formula rendered without surrounding paragraph wrappers. */
interface InlineLatexProps {
  latex: string
  display?: boolean
  className?: string
}

/** Typeset a single LaTeX expression into an inline span so it can sit inside buttons, chips, and selectable expression tokens. */
export function InlineLatex({ latex, display = false, className }: InlineLatexProps) {
  const html = katex.renderToString(latex, {
    displayMode: display,
    throwOnError: false,
    strict: 'ignore',
  })
  const combinedClass = className === undefined ? 'chat-latex' : `chat-latex ${className}`
  return <span className={combinedClass} dangerouslySetInnerHTML={{ __html: html }} />
}

/** Render Markdown prose, inline code, `$...$` inline math, and `$$...$$` display math for chat messages, context previews, and agent replies. */
export function ChatMarkdown({ content, className }: { content: string; className?: string }) {
  const combinedClass = className === undefined ? 'chat-markdown' : `chat-markdown ${className}`
  return (
    <div className={combinedClass}>
      <Markdown remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[rehypeKatex]} skipHtml>
        {content}
      </Markdown>
    </div>
  )
}
