/**
 * Render a notebook page from its record, with a title, ordered content, display settings, and direct actions for writing, mathematics, and the optional graph workspace. This view does not store the page.
 *
 * @file
 */

import type { CSSProperties, ChangeEvent, ReactNode } from 'react'
import { Button } from '#/component-library/button'
import { ChartLine } from 'lucide-react'
import { MathIcon, MarkdownIcon } from '#/component-library/icons/folio-icons.tsx'
import { LatexCell } from './latex-cell'
import { MarkdownCell } from './markdown-cell'
import { PageMenuView } from './page-menu-view'
import type { NotebookCell } from '#/notebook/notebook-cells.ts'
import { cellSource } from '#/notebook/notebook-cells.ts'
import { blockDepth } from '#/notebook/notebook-blocks'
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
  onOpenGraph?: () => void
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
    <div className="cell" key={cell.cellId} style={{ marginInlineStart: blockDepth(cell) * 24 }}>
      {cell.kind === 'graph' ? (
        <figure className="notebook-graph">
          <img src={cell.snapshot.image} width={cell.snapshot.width} height={cell.snapshot.height} alt={`${cell.graph.dimension.toUpperCase()} graph: ${cellSource(cell)}`} />
        </figure>
      ) : cell.kind === 'math' ? (
        <LatexCell caption={cell.caption} editorMode={props.page.pageMetadata.editorMode} cellId={cell.cellId} initialLatex={cell.latex} onLatexChange={readOnly ? ignoreLatexChange : props.onLatexChange} readOnly={readOnly} />
      ) : (
        <MarkdownCell editorMode={props.page.pageMetadata.editorMode} cellId={cell.cellId} markdown={cell.markdown} onMarkdownChange={readOnly ? ignoreMarkdownChange : props.onMarkdownChange} readOnly={readOnly} />
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

/** Offer direct content actions instead of hiding the first writing step inside a menu. */
function NewCellControl({ onAddMathCell, onAddMarkdownCell, onOpenGraph, empty }: { onAddMathCell: () => void; onAddMarkdownCell: () => void; onOpenGraph?: () => void; empty: boolean }) {
  return (
    <div className={empty ? 'page-start-actions' : 'add-cell-actions'} aria-label="Add to page">
      <Button variant={empty ? 'default' : 'quiet'} onClick={onAddMarkdownCell}>
        <MarkdownIcon />
        {empty ? 'Write a note' : 'Text'}
      </Button>
      <Button variant="quiet" onClick={onAddMathCell}>
        <MathIcon />
        {empty ? 'Add math' : 'Math'}
      </Button>
      {onOpenGraph && (
        <Button variant="quiet" onClick={onOpenGraph}>
          <ChartLine size={16} aria-hidden="true" />
          {empty ? 'Explore a graph' : 'Graph'}
        </Button>
      )}
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
      {page.cells.length === 0 ? <p className="page-empty">{props.interaction === 'view' ? 'This page is empty.' : 'Start with a thought, an equation, or a question.'}</p> : null}
      {props.content}
      {props.interaction === 'editable' ? <NewCellControl onAddMathCell={props.onAddMathCell} onAddMarkdownCell={props.onAddMarkdownCell} onOpenGraph={props.onOpenGraph} empty={page.cells.length === 0} /> : null}
    </section>
  )
}
