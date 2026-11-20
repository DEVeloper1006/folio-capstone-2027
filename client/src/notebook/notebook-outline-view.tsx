/**
 * Subscribe only expanded pages to their live outline. Keyboard-accessible heading buttons open the target page and focus the corresponding rendered heading.
 *
 * @file
 */
import { usePageSelection } from './use-page-state'
import { pageHeadings } from './notebook-outline'
import type { PageHeading } from './notebook-outline'

/** Show headings in document order, indented by their hierarchy. */
export function NotebookOutlineView({ pageId, onNavigate }: { pageId: string; onNavigate: (pageId: string, heading: PageHeading) => void }) {
  const headings = usePageSelection(pageId, pageHeadings)
  /** Open one exact heading, even when another heading has the same text. */
  function renderHeading(heading: PageHeading) {
    /** Delegate navigation without changing the document. */
    function navigate() {
      onNavigate(pageId, heading)
    }
    return (
      <li key={`${heading.cellId}:${heading.ordinal}`}>
        <button className="page-outline-link" style={{ paddingInlineStart: 24 + (heading.level - 1) * 12 }} onClick={navigate} title={heading.title}>
          {heading.title}
        </button>
      </li>
    )
  }
  return (
    <ul className="page-outline" aria-label="Page headings">
      {headings?.length ? headings.map(renderHeading) : <li className="page-outline-empty">No headings yet</li>}
    </ul>
  )
}
