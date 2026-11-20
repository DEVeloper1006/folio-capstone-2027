/**
 * Derive page outlines with the same Markdown parser and extensions used by the editor. Address repeated headings by cell identity and ordinal rather than their display text.
 *
 * @file
 */
import { MarkdownManager } from '@tiptap/markdown'
import type { JSONContent } from '@tiptap/react'
import { markdownExtensions } from '../component-library/markdown-rich-field'
import type { Page } from './page'

export interface PageHeading {
  cellId: string
  ordinal: number
  level: number
  title: string
}
export interface HeadingTarget extends PageHeading {
  pageId: string
  request: number
}
const markdown = new MarkdownManager({ extensions: markdownExtensions })

/** Read plain heading text, retaining inline math without duplicating its rendered accessibility text. */
function headingText(node: JSONContent): string {
  const latex: unknown = node.attrs?.latex
  if (node.type === 'inlineMath' && typeof latex === 'string') return latex
  return node.text ?? node.content?.map(headingText).join('') ?? ''
}
/** Index Markdown headings and math captions, excluding fenced code and graph images. */
export function pageHeadings(page: Page): PageHeading[] {
  const headings: PageHeading[] = []
  for (const cell of page.cells) {
    const source = cell.kind === 'markdown' ? cell.markdown : cell.kind === 'math' ? cell.caption : undefined
    if (!source) continue
    let ordinal = 0
    /** Traverse source order including headings nested in quotes and lists. */
    function visit(node: JSONContent) {
      const level: unknown = node.attrs?.level
      if (node.type === 'heading' && typeof level === 'number') headings.push({ cellId: cell.cellId, ordinal: ordinal++, level, title: headingText(node) || 'Untitled heading' })
      node.content?.forEach(visit)
    }
    visit(markdown.parse(source))
  }
  return headings
}
