/**
 * Describe a notebook page independently of how it is rendered. Contains the page identifier, the ordered cells it holds, and the display metadata stored with that page.
 *
 * @file
 */

import type { NotebookCell } from './notebook-cells.ts'

/** Choose how wide the page content is. Regular uses the notebook's centered column; full uses the available width. */
export type PageWidth = 'regular' | 'full'

/** Store the information used to display a page. Cell spacing is the vertical distance between cells, in pixels, matching the rest of the notebook layout. */
export interface PageMetadata {
  title: string
  cellSpacingPx: number
  width: PageWidth
}

/** Hold one page's identity, its cells in display order, and the metadata used when that page is shown. */
export interface Page {
  pageId: string
  cells: readonly NotebookCell[]
  pageMetadata: PageMetadata
}
