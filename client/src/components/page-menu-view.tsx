/**
 * Render the page display menu. Contains the shared popover, cell-editing mode, cell-spacing field, and page-width choice.
 *
 * @file
 */

import type { ChangeEvent } from 'react'
import { Popover, SegmentedControl, TextField } from '#/component-library/index.ts'
import type { SegmentedOption } from '#/component-library/index.ts'
import type { CellEditorMode, PageMetadata, PageWidth } from '#/notebook/page.ts'

/** Receive the current display metadata and report a replacement when spacing or width changes. */
interface PageMenuViewProps {
  pageMetadata: PageMetadata
  onPageMetadataChange: (pageMetadata: PageMetadata) => void
}

const pageWidthOptions: ReadonlyArray<SegmentedOption<PageWidth>> = [
  { value: 'narrow', label: 'Narrow' },
  { value: 'full', label: 'Full' },
]

/** Show a top-right menu that edits the vertical distance between cells and the page width. */
export function PageMenuView({ pageMetadata, onPageMetadataChange }: PageMenuViewProps) {
  /** Store a non-negative pixel distance between cells. */
  function handleSpacingChange(event: ChangeEvent<HTMLInputElement>) {
    const cellSpacingPx = event.target.valueAsNumber
    if (!Number.isFinite(cellSpacingPx) || cellSpacingPx < 0) return
    onPageMetadataChange({ ...pageMetadata, cellSpacingPx })
  }

  /** Store the selected page width. */
  function handleWidthChange(width: PageWidth) {
    onPageMetadataChange({ ...pageMetadata, width })
  }

  /** Apply one editing mode to every cell on this page. */
  function handleEditorModeChange(editorMode: CellEditorMode) {
    onPageMetadataChange({ ...pageMetadata, editorMode })
  }

  return (
    <div className="page-menu">
      <Popover label="Page display" trigger="···" align="end">
        <SegmentedControl<CellEditorMode>
          label="Cell editing"
          value={pageMetadata.editorMode}
          options={[
            { value: 'rich', label: 'Rich' },
            { value: 'source', label: 'Source' },
          ]}
          onValueChange={handleEditorModeChange}
        />
        <TextField label="Cell spacing" type="number" min={0} step={4} suffix="px" value={pageMetadata.cellSpacingPx} onChange={handleSpacingChange} />
        <SegmentedControl label="Page width" value={pageMetadata.width} options={pageWidthOptions} onValueChange={handleWidthChange} />
      </Popover>
    </div>
  )
}
