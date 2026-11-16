/**
 * Render one notebook page from the record it is given. Contains the page title, the ordered cells and, in the editable variant, the title field, the spacing and width menu, and the control that appends a cell. This view does not store the page.
 *
 * @file
 */

import { useState } from 'react'
import type { CSSProperties, ChangeEvent, ReactNode } from 'react'
import { Menu } from '@base-ui/react/menu'
import { MathIcon, MarkdownIcon } from '#/component-library/icons/folio-icons.tsx'
import { LatexCell } from './latex-cell'
import { MarkdownCell } from './markdown-cell'
import { PageMenuView } from './page-menu-view'
import type { NotebookCell } from '#/notebook/notebook-cells.ts'
import type { Page, PageMetadata } from '#/notebook/page.ts'

/** Choose whether the page accepts edits. `view` shows the stored cells and hides editing controls. */
export type PageInteraction = 'editable' | 'view'

/** Receive the page to display and the notebook callbacks that change its cells. */
interface EditablePageViewProps {
  page: Page
  interaction: 'editable'
  onLatexChange: (cellId: string, latex: string) => void
  onMarkdownChange: (cellId: string, markdown: string) => void
  onAddMathCell: () => void
  onAddMarkdownCell: () => void
  onTitleChange: (title: string) => void
  onPageMetadataChange: (pageMetadata: PageMetadata) => void
}

/** Receive a page to display without editing it. */
interface ViewPageProps {
  page: Page
  interaction: 'view'
}

/** The editable page requires its change callbacks. The view-only page does not. */
export type PageViewProps = EditablePageViewProps | ViewPageProps

/** Render the editor that matches a cell's kind. A view-only cell does not report edits. */
function renderCell(cell: NotebookCell, props: PageViewProps) {
  const readOnly = props.interaction === 'view'
  return (
    <div className="cell" key={cell.cellId}>
      {cell.kind === 'math' ? (
        <LatexCell cellId={cell.cellId} initialLatex={cell.latex} onLatexChange={readOnly ? ignoreLatexChange : props.onLatexChange} readOnly={readOnly} />
      ) : (
        <MarkdownCell cellId={cell.cellId} markdown={cell.markdown} onMarkdownChange={readOnly ? ignoreMarkdownChange : props.onMarkdownChange} readOnly={readOnly} />
      )}
    </div>
  )
}

/** Ignore a formula edit from a view-only cell. The page record stays as it was given. */
function ignoreLatexChange() {}

/** Ignore a Markdown edit from a view-only cell. The page record stays as it was given. */
function ignoreMarkdownChange() {}

/** Show the page name as a heading. A view-only page with a blank title reads "Untitled". */
function PageTitleHeading({ title }: { title: string }) {
  return <h1 className="page-title">{title || 'Untitled'}</h1>
}

/** Edit the page name. A blank field shows the placeholder and stores the empty string. */
function EditablePageTitle({ title, onTitleChange }: { title: string; onTitleChange: (title: string) => void }) {
  /** Store the title as it is typed. */
  function handleTitleChange(event: ChangeEvent<HTMLInputElement>) {
    onTitleChange(event.target.value)
  }

  return <input className="page-title" aria-label="Page title" placeholder="Untitled" value={title} onChange={handleTitleChange} />
}

/** Append a cell. Hovering offers math or Markdown; clicking repeats the kind of the cell above, or math when the page has no cells. */
function NewCellControl({ cells, onAddMathCell, onAddMarkdownCell }: { cells: readonly Pick<NotebookCell, 'kind'>[]; onAddMathCell: () => void; onAddMarkdownCell: () => void }) {
  const [open, setOpen] = useState(false)
  const previousKind = cells.at(-1)?.kind ?? 'math'

  /** Append another cell of the same kind as the last one on the page. */
  function addCellLikePrevious() {
    if (previousKind === 'math') onAddMathCell()
    else onAddMarkdownCell()
  }

  /** Open the kind list on hover. A press on the button itself repeats the previous kind and leaves the list closed. */
  function handleOpenChange(next: boolean, details: { reason: string }) {
    if (details.reason === 'trigger-press') {
      addCellLikePrevious()
      setOpen(false)
      return
    }
    setOpen(next)
  }

  return (
    <div className="add-cell-actions">
      <Menu.Root open={open} onOpenChange={handleOpenChange} modal={false}>
        <Menu.Trigger className="ui-button ui-button-quiet" openOnHover delay={160} closeDelay={120}>
          New Cell
        </Menu.Trigger>
        <Menu.Portal>
          <Menu.Positioner side="bottom" sideOffset={6} align="start">
            <Menu.Popup className="primitive-popup">
              <Menu.Item className="primitive-item" onClick={onAddMathCell}>
                <span className="primitive-item-label">
                  <MathIcon /> Math
                </span>
              </Menu.Item>
              <Menu.Item className="primitive-item" onClick={onAddMarkdownCell}>
                <span className="primitive-item-label">
                  <MarkdownIcon /> Markdown
                </span>
              </Menu.Item>
            </Menu.Popup>
          </Menu.Positioner>
        </Menu.Portal>
      </Menu.Root>
    </div>
  )
}

/** Show the page title and its cells at the configured spacing. The editable variant also changes the title, display metadata, and appends cells. */
export function PageView(props: PageViewProps) {
  const { page } = props
  /** Render a cell from the supplied page. */
  function renderPageCell(cell: NotebookCell) {
    return renderCell(cell, props)
  }
  return <PageFrame {...props} page={page} content={page.cells.map(renderPageCell)} />
}

type FrameProps = (Omit<EditablePageViewProps, 'page' | 'onLatexChange' | 'onMarkdownChange'> | Omit<ViewPageProps, 'page'>) & { page: Omit<Page, 'cells'> & { cells: readonly Pick<NotebookCell, 'cellId' | 'kind'>[] }; content: ReactNode }

/** Share page layout and controls between notebook and gallery views. */
export function PageFrame(props: FrameProps) {
  const { page } = props
  const cellListStyle: CSSProperties = { gap: page.pageMetadata.cellSpacingPx }
  return (
    <section className="page" aria-label={page.title || 'Untitled'} style={cellListStyle}>
      {props.interaction === 'editable' ? <PageMenuView pageMetadata={page.pageMetadata} onPageMetadataChange={props.onPageMetadataChange} /> : null}
      {props.interaction === 'editable' ? <EditablePageTitle title={page.title} onTitleChange={props.onTitleChange} /> : <PageTitleHeading title={page.title} />}
      {page.cells.length === 0 ? <p className="page-empty">{props.interaction === 'view' ? 'This page is empty.' : 'This page has no cells yet.'}</p> : null}
      {props.content}
      {props.interaction === 'editable' ? <NewCellControl cells={page.cells} onAddMathCell={props.onAddMathCell} onAddMarkdownCell={props.onAddMarkdownCell} /> : null}
    </section>
  )
}
