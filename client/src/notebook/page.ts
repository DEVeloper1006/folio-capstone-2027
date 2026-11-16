/**
 * Describe a notebook page independently of how it is rendered. Contains the page identifier, its title, the ordered cells it holds, the display metadata stored with that page, and creation of an empty page.
 *
 * @file
 */

import { createCellId } from './notebook-cells.ts'
import type { NotebookCell } from './notebook-cells.ts'

/** Choose how wide the page content is. Narrow uses the notebook's centered column; full uses the available width. */
export type PageWidth = 'narrow' | 'full'

/** Store the information used to display a page. Cell spacing is the vertical distance between cells, in pixels, matching the rest of the notebook layout. */
export interface PageMetadata {
  cellSpacingPx: number
  width: PageWidth
}

/** Hold one page's identity, its title, its cells in display order, and the metadata used when that page is shown. */
export interface Page {
  pageId: string
  title: string
  cells: readonly NotebookCell[]
  pageMetadata: PageMetadata
}

/** The display metadata used by a page that has not chosen its own spacing or width. */
export const defaultPageMetadata: PageMetadata = {
  cellSpacingPx: 16,
  width: 'narrow',
}

/** Create a page with no cells. The caller supplies the title and the page receives a new id. */
export function createEmptyPage(title: string): Page {
  return { pageId: createCellId(), title, cells: [], pageMetadata: { ...defaultPageMetadata } }
}

/** Choose the next "Untitled" title that is not already used by a page. */
export function nextUntitledTitle(pages: readonly Pick<Page, 'title'>[]) {
  /** Report whether a page already shows this title. */
  function titleIsUsed(title: string) {
    /** Compare one page's title with the candidate. */
    function hasTitle(page: Pick<Page, 'title'>) {
      return page.title === title
    }
    return pages.some(hasTitle)
  }

  if (!titleIsUsed('Untitled')) return 'Untitled'
  let suffix = 2
  while (titleIsUsed(`Untitled ${suffix}`)) suffix += 1
  return `Untitled ${suffix}`
}
