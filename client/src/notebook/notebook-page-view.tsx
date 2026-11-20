/**
 * Render a nested notebook from query subscriptions, track cell selection and editing, and share subtree movement, nesting, deletion, and restore operations between drag handles, menus, and cell commands.
 *
 * @file
 */
import './focus-cell-dialog.css'
import type { HeadingTarget } from './notebook-outline'
import { mathSection, sectionMode } from '../math-help/math-context'
import { appliedSettingsKey } from '../settings/use-settings'
import { defaultSettings } from '../settings/settings'
import { Dialog } from '@base-ui/react/dialog'
import { Button } from '#/component-library/button'
import { TextField } from '#/component-library/text-field'
import { useEffect, useLayoutEffect, useImperativeHandle, useRef, useState } from 'react'
import type { ClipboardEvent, FormEvent, Ref } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { PageFrame } from '#/components/page-view'
import { CellFrame } from '#/component-library/cell-frame'
import { NotebookBlockView } from './notebook-block-view'
import { blockDepth, blockEnd, blockIndex, blockDestination, moveBlock, deleteBlock, restoreBlock } from './notebook-blocks'
import type { BlockAction, BlockPlacement, BlockSlot } from './notebook-blocks'
import { LatexCell } from '#/components/latex-cell'
import { MarkdownCell } from '#/components/markdown-cell'
import { appendCell, editCell, notebookCommands, usePageSelection } from './use-page-state'
import { createCellId, pastedLatex, cellSource } from './notebook-cells'
import type { NotebookCell } from './notebook-cells'
import type { CellEditorMode, Page, PageMetadata } from './page'
import { shortcutKey, defaultOverrides } from '#/editor/commands/shortcut-overrides'
import type { ShortcutOverrides } from '#/editor/commands/shortcut-overrides'
import type { CommandContext } from '#/editor/commands/editor-commands'

/** Expose live interaction context and command dispatch to the workspace listener. */
export interface NotebookCommandController {
  run: (id: string) => boolean
  getContext: () => CommandContext
}
/** Select the layout fields that change independently of a cell's text. */
function pageLayout(page: Page): Omit<Page, 'cells'> & { cells: readonly BlockSlot[] } {
  /** Keep each cell's identity and kind for ordering and the add-cell control. */
  function cellSlot({ cellId, kind, depth }: NotebookCell) {
    return { cellId, kind, depth }
  }
  return { ...page, cells: page.cells.map(cellSlot) }
}

/** Subscribe one editor to its cell and write changes against that page's latest document. */
function NotebookCellEditor({
  editorMode,
  pageId,
  index,
  cellId,
  editing,
  focused,
  selected,
  setEditing,
  onEditGraph,
}: {
  editorMode: CellEditorMode
  pageId: string
  index: number
  cellId: string
  editing: boolean
  focused: boolean
  selected: boolean
  setEditing: (id: string | null) => void
  onEditGraph?: (id: string) => void
}) {
  const client = useQueryClient()
  /** Ignore a stale slot while the layout is changing. */
  function selectCell(page: Page) {
    const cell = page.cells.at(index)
    return cell?.cellId === cellId ? cell : undefined
  }
  const cell = usePageSelection(pageId, selectCell)
  const { data: settings } = useQuery({ queryKey: appliedSettingsKey, initialData: defaultSettings, enabled: false })
  /** Store the edited source on the page containing this field. */
  function changeSource(id: string, source: string) {
    /** Apply the edit to the latest document. */
    function update(page: Page) {
      return editCell(page, id, source)
    }
    notebookCommands(client).updatePage(pageId, update)
  }
  /** Save this math cell’s Markdown caption with its existing formula. */
  function changeCaption(caption: string) {
    notebookCommands(client).updatePage(pageId, (page) => ({
      ...page,
      cells: page.cells.map((item) => (item.cellId === cellId && item.kind === 'math' ? { ...item, caption } : item)),
    }))
  }
  /** Activate this cell through its normal edit control. */
  function beginEditing() {
    setEditing(cellId)
  }
  /** Finish or begin editing the current Markdown cell. */
  function changeEditing(value: boolean) {
    setEditing(value ? cellId : null)
  }
  /** Reopen the saved graph with its source and captured view. */
  function editGraph() {
    onEditGraph?.(cellId)
  }
  /** Scope notation completion to the current problem and its selected subject. Missing modes disable optional completion. */
  function previousSteps() {
    const page = notebookCommands(client).getPage(pageId)
    if (!page) return undefined
    try {
      const mode = sectionMode(page, cellId, settings.math)
      return `${mode.title}: ${mode.summary}\n${mathSection(page, cellId)?.previous ?? ''}`.slice(0, 12000)
    } catch {
      return undefined
    }
  }
  if (!cell) return null
  return (
    <CellFrame state={editing ? 'editing' : focused ? 'focused' : selected ? 'selected' : 'unselected'} role="group" tabIndex={0} aria-label={`${cell.kind === 'graph' ? 'Graph' : cell.kind === 'math' ? 'Math' : 'Markdown'} cell ${index + 1}`} data-cell-id={cellId}>
      {cell.kind === 'graph' ? (
        <figure className="notebook-graph">
          <button className="notebook-graph-image" onClick={editGraph} aria-label="Edit graph">
            <img src={cell.snapshot.image} width={cell.snapshot.width} height={cell.snapshot.height} alt={`${cell.graph.dimension.toUpperCase()} graph: ${cellSource(cell)}`} />
          </button>
          <figcaption>
            <span>{cellSource(cell)}</span>
            <Button variant="quiet" onClick={editGraph}>
              Edit graph
            </Button>
          </figcaption>
        </figure>
      ) : cell.kind === 'math' ? (
        <LatexCell caption={cell.caption} onCaptionChange={changeCaption} previous={editing ? previousSteps() : undefined} editorMode={editorMode} cellId={cellId} editing={editing} onBeginEditing={beginEditing} initialLatex={cell.latex} onLatexChange={changeSource} />
      ) : (
        <MarkdownCell editorMode={editorMode} cellId={cellId} editing={editing} onEditingChange={changeEditing} markdown={cell.markdown} onMarkdownChange={changeSource} />
      )}
      <div data-math-help-slot={cellId} />
    </CellFrame>
  )
}

/** Render a cached page. Only layout changes update the frame and only the edited cell receives new source. */
export function NotebookPageView({
  pageId,
  headingTarget,
  commandRef,
  onOpenGraph,
  onEditGraph,
  onActiveCellChange,
}: {
  pageId: string
  headingTarget?: HeadingTarget
  commandRef: Ref<NotebookCommandController>
  onOpenGraph?: () => void
  onEditGraph?: (id: string) => void
  onActiveCellChange?: (id: string) => void
}) {
  const client = useQueryClient()
  const page = usePageSelection(pageId, pageLayout)
  const { updatePage, renamePage, getPage } = notebookCommands(client)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [cellMode, setCellMode] = useState<CommandContext['cellMode']>('idle')
  /** Enter edit mode for a cell, or return to cell selection when editing finishes. */
  function setEditing(id: string | null) {
    /** Recognize graph cells so keyboard edit commands open the panel. */
    function isGraph(cell: NotebookCell) {
      return cell.cellId === id && cell.kind === 'graph'
    }
    if (id && getPage(pageId)?.cells.some(isGraph)) {
      onEditGraph?.(id)
      return
    }
    setEditingId(id)
    setCellMode(id ? 'editing' : 'selection')
    if (id) setSelected(id)
  }
  const notebookRef = useRef<HTMLElement>(null)
  const [viewingId, setViewing] = useState<string | null>(null)
  const [selectedId, setSelected] = useState<string | null>(null)
  /** Retain the last selected notebook block while focus moves into a side panel. */
  function publishSelection() {
    if (selectedId) onActiveCellChange?.(selectedId)
  }
  useEffect(publishSelection, [selectedId, onActiveCellChange])
  const [notice, setNotice] = useState('')
  const visitedHeading = useRef<HeadingTarget | undefined>(undefined)
  /** Close the editor, then focus the heading only after React commits its rendered preview. */
  function visitHeading() {
    if (!headingTarget || headingTarget.pageId !== pageId || visitedHeading.current === headingTarget || !page) return
    if (editingId !== null) {
      setEditingId(null)
      return
    }
    const row = notebookRef.current?.querySelector<HTMLElement>(`[data-cell-id="${CSS.escape(headingTarget.cellId)}"]`)
    const heading = row?.querySelectorAll<HTMLElement>('h1,h2,h3,h4,h5,h6').item(headingTarget.ordinal)
    visitedHeading.current = headingTarget
    if (!heading) {
      setNotice('This heading changed. Select it again from the page outline.')
      return
    }
    setSelected(headingTarget.cellId)
    notebookRef.current?.querySelector('[data-heading-target]')?.removeAttribute('data-heading-target')
    heading.setAttribute('data-heading-target', '')
    heading.tabIndex = -1
    heading.focus({ preventScroll: true })
    heading.scrollIntoView({ block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' })
  }
  useLayoutEffect(visitHeading, [headingTarget, pageId, editingId, page])
  const [draggedId, setDraggedId] = useState<string | null>(null)
  /** Save structural changes before updating selection; report storage errors without hiding the previous document. */
  function changeBlocks(change: (current: Page) => Page, message: string, focusId?: string) {
    try {
      updatePage(pageId, change)
      setNotice(message)
      /** Refocus the moved block's handle after React has placed its subtree. */
      function focusBlock() {
        if (!focusId) {
          selectRow()
          return
        }
        const block = notebookRef.current?.querySelector<HTMLElement>(`[data-block-id="${CSS.escape(focusId)}"] .block-drag-handle`)
        block?.focus({ preventScroll: true })
        block?.scrollIntoView({ block: 'nearest' })
      }
      requestAnimationFrame(focusBlock)
    } catch (cause) {
      setNotice(cause instanceof Error ? cause.message : 'Could not save the block change. Your page is unchanged.')
    }
  }
  /** Move one subtree using the latest stored order, regardless of how the action was initiated. */
  function relocateBlock(id: string, targetId: string, placement: BlockPlacement) {
    /** Keep all descendants with the moving block. */
    function move(current: Page) {
      return moveBlock(current, id, targetId, placement)
    }
    changeBlocks(move, placement === 'inside' ? 'Block nested. Its contents moved with it.' : 'Block moved.', id)
  }
  /** Route the handle menu and keyboard actions through the same subtree operations. */
  function blockAction(id: string, action: BlockAction) {
    if (action === 'delete') {
      /** Retain deleted blocks in the saved page for undo, including graph snapshots. */
      function remove(current: Page) {
        return deleteBlock(current, id)
      }
      changeBlocks(remove, 'Block deleted. Press Command or Control Z to restore it.')
      return
    }
    const current = getPage(pageId)
    const destination = current && blockDestination(current.cells, id, action)
    if (destination) relocateBlock(id, destination.targetId, destination.placement)
  }
  /** Restore the most recently deleted subtree without reverting newer edits. */
  function undoBlockDelete() {
    const id = getPage(pageId)?.deletedBlocks?.at(-1)?.cells[0]?.cellId
    changeBlocks(restoreBlock, 'Deleted block restored.', id)
  }
  const [focusPickerOpen, setFocusPickerOpen] = useState(false)
  const focusPickerTarget = useRef<string | null>(null)
  /** Mount the chosen editor only after the modal has released focus and made the notebook interactive again. */
  function finishFocusPicker(open: boolean) {
    if (open) return
    const id = focusPickerTarget.current
    focusPickerTarget.current = null
    if (id) setEditing(id)
    else notebookRef.current?.focus()
  }
  /** Focus a numbered cell through a dialog supported by both browsers and Electron. */
  function focusNumberedCell(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const position = Number(new FormData(event.currentTarget).get('position'))
    const slot = getPage(pageId)?.cells.at(position - 1)
    if (!Number.isInteger(position) || position < 1 || !slot) return
    focusPickerTarget.current = slot.cellId
    setFocusPickerOpen(false)
  }
  /** Select a row in view mode and give it keyboard focus. */
  function selectRow(id?: string) {
    setEditingId(null)
    setCellMode(id ? 'selection' : 'idle')
    setViewing(null)
    setSelected(id ?? null)
    const row = id && notebookRef.current?.querySelector<HTMLElement>(`[data-cell-id="${CSS.escape(id)}"]`)
    if (row) row.focus()
    else notebookRef.current?.focus({ preventScroll: true })
  }
  /** Copy the latest LaTeX or Markdown source as plain text. */
  async function copyCell(id: string) {
    const current = getPage(pageId)
    /** Identify the cell being copied. */
    function matches(cell: NotebookCell) {
      return cell.cellId === id
    }
    const cell = current?.cells.find(matches)
    if (!cell) return
    try {
      await navigator.clipboard.writeText(cellSource(cell))
      setNotice('Cell copied')
    } catch {
      setNotice('Could not copy the cell to the clipboard.')
    }
  }

  /** Replace the requested cell's source while preserving its identity and kind. */
  function pasteSource(id: string, text: string) {
    /** Apply clipboard text to the latest stored cell. */
    function replace(current: Page) {
      /** Identify the destination so Markdown retains its source delimiters. */
      function matches(cell: NotebookCell) {
        return cell.cellId === id
      }
      const cell = current.cells.find(matches)
      if (cell?.kind === 'graph') throw new Error('Use Edit graph to change this figure.')
      return editCell(current, id, cell?.kind === 'math' ? pastedLatex(text) : text)
    }
    updatePage(pageId, replace)
    setNotice('Cell contents pasted')
  }
  /** Read clipboard text for a palette action or a custom paste shortcut. */
  async function pasteCell(id: string) {
    try {
      pasteSource(id, await navigator.clipboard.readText())
    } catch (cause) {
      setNotice(cause instanceof Error ? cause.message : 'Clipboard unavailable. Use Cmd/Ctrl+V on the selected cell.')
    }
  }
  /** Put source text on the native clipboard when copying a selected row. */
  function handleCellCopy(event: ClipboardEvent<HTMLElement>) {
    const overrides = client.getQueryData<ShortcutOverrides>(shortcutKey) ?? defaultOverrides
    if (cellMode !== 'selection' || !selectedId || Object.hasOwn(overrides, 'workspace.currentPage.cell.copySelected')) return
    const target = event.target
    if (!(target instanceof Element) || !target.closest('[data-cell-id]')) return
    /** Read the selected cell's latest source. */
    function matches(cell: NotebookCell) {
      return cell.cellId === selectedId
    }
    const cell = getPage(pageId)?.cells.find(matches)
    if (!cell) return
    event.clipboardData.setData('text/plain', cellSource(cell))
    event.preventDefault()
    event.stopPropagation()
    setNotice('Cell copied')
  }

  /** Use the browser paste event for default bindings, avoiding a separate clipboard permission request. */
  function handleCellPaste(event: ClipboardEvent<HTMLElement>) {
    const overrides = client.getQueryData<ShortcutOverrides>(shortcutKey) ?? defaultOverrides
    if (cellMode !== 'selection' || !selectedId || Object.hasOwn(overrides, 'workspace.currentPage.cell.pasteSelected')) return
    const target = event.target
    if (!(target instanceof Element) || !target.closest('[data-cell-id]') || !event.clipboardData.types.includes('text/plain')) return
    event.preventDefault()
    event.stopPropagation()
    /** Identify whether the target accepts the LaTeX clipboard representation. */
    function matches(cell: NotebookCell) {
      return cell.cellId === selectedId
    }
    const cell = getPage(pageId)?.cells.find(matches)
    if (cell?.kind === 'graph') {
      setNotice('Use Edit graph to change this figure.')
      return
    }
    const math = cell?.kind === 'math'
    const latex = math ? event.clipboardData.getData('application/x-latex') : ''
    pasteSource(selectedId, latex || event.clipboardData.getData('text/plain'))
  }

  /** Finish the active editor or insert a sibling using the current stored source. */
  function runCellCommand(command: string, id: string | null): boolean {
    if (!page) return false
    const cells = page.cells
    /** Find the selected row in display order. */
    function isCurrent(cell: Pick<NotebookCell, 'cellId'>) {
      return cell.cellId === id
    }
    const index = cells.findIndex(isCurrent)
    const first = cells.at(0)?.cellId
    const last = cells.at(-1)?.cellId
    switch (command) {
      case 'workspace.page.undoDelete':
        if (cellMode === 'editing' || !page.deletedBlocks?.length) return false
        undoBlockDelete()
        return true
      case 'workspace.page.editRich':
      case 'workspace.page.editSource':
        setMetadata({ ...page.pageMetadata, editorMode: command.endsWith('editSource') ? 'source' : 'rich' })
        return true
      case 'workspace.page.scrollTop':
        window.scrollTo(0, 0)
        return true
      case 'workspace.page.scrollBottom':
        window.scrollTo(0, document.documentElement.scrollHeight)
        return true
      case 'workspace.page.display':
        notebookRef.current?.querySelector<HTMLButtonElement>('.page-menu button')?.click()
        return true
      case 'workspace.page.full':
      case 'workspace.page.narrow':
        setMetadata({ ...page.pageMetadata, width: command.endsWith('.full') ? 'full' : 'narrow' })
        return true
      case 'workspace.currentPage.cell.addMath':
        addMath()
        return true
      case 'workspace.currentPage.cell.addMarkdown':
        addMarkdown()
        return true
      case 'workspace.currentPage.cell.add':
        if (cells.at(-1)?.kind === 'markdown') addMarkdown()
        else addMath()
        return true
      case 'workspace.currentPage.cell.selectFirst':
        selectRow(first)
        return !!first
      case 'workspace.currentPage.cell.selectLast':
        selectRow(last)
        return !!last
      case 'workspace.currentPage.cell.select':
        selectRow(id ?? first)
        return !!first
      case 'workspace.currentPage.cell.selectNext':
        selectRow(cells[Math.min(index + 1, cells.length - 1)]?.cellId)
        return !!first
      case 'workspace.currentPage.cell.selectPrevious':
        selectRow(index < 0 ? last : cells[Math.max(0, index - 1)]?.cellId)
        return !!first
      case 'workspace.currentPage.cell.focusFirst':
        setEditing(first ?? null)
        return !!first
      case 'workspace.currentPage.cell.focusLast':
        setEditing(last ?? null)
        return !!last
      case 'workspace.currentPage.cell.focusAt': {
        setFocusPickerOpen(true)
        return true
      }
    }
    if (!id) return false
    const source = cells.at(index)
    if (index < 0 || !source) return false
    if (command === 'workspace.currentPage.cell.view') {
      selectRow(id)
      const selector = `[data-cell-id="${CSS.escape(id)}"] .notebook-live-cell-body [tabindex="0"]`
      /** Focus the rendered contents after React has closed an active editor. */
      function focusPreview() {
        notebookRef.current?.querySelector<HTMLElement>(selector)?.focus()
      }
      requestAnimationFrame(focusPreview)
      return true
    }
    if (command === 'workspace.currentPage.cell.edit') {
      setEditing(id)
      return true
    }
    if ((command === 'workspace.currentPage.cell.copySelected' || command === 'workspace.currentPage.cell.pasteSelected') && cellMode !== 'selection') return false
    if (command === 'workspace.currentPage.cell.pasteSelected') {
      void pasteCell(id)
      return true
    }
    if (command === 'workspace.currentPage.cell.copy' || command === 'workspace.currentPage.cell.copySelected') {
      void copyCell(id)
      return true
    }
    if ((command === 'workspace.currentPage.cell.delete' || command === 'workspace.currentPage.cell.deleteSelected') && cellMode !== 'selection') return false
    if (command === 'workspace.currentPage.cell.delete' || command === 'workspace.currentPage.cell.deleteSelected') {
      blockAction(id, 'delete')
      return true
    }
    if (command === 'workspace.currentPage.cell.unfocus') {
      selectRow(id)
      return true
    }
    const duplicate = command === 'workspace.currentPage.cell.duplicateBelow'
    if (duplicate ? source.kind !== 'math' : command !== 'workspace.currentPage.cell.createBelow' && command !== 'workspace.currentPage.cell.createAbove') return false
    const cellId = createCellId()
    /** Insert after the source in the latest page, leaving its content untouched. */
    function insert(current: Page) {
      const sourceIndex = current.cells.findIndex(isCurrent)
      const original = current.cells.at(sourceIndex)
      if (sourceIndex < 0 || !original) return current
      const depth = blockDepth(original)
      const cell: NotebookCell = original.kind === 'math' ? { cellId, depth, kind: 'math', ...(duplicate ? { latex: original.latex, caption: original.caption } : { latex: '' }) } : { cellId, depth, kind: 'markdown', markdown: '' }
      const nextCells = [...current.cells]
      nextCells.splice(command.endsWith('createAbove') ? sourceIndex : blockEnd(current.cells, sourceIndex), 0, cell)
      return { ...current, cells: nextCells }
    }
    updatePage(pageId, insert)
    setSelected(cellId)
    setEditing(cellId)
    return true
  }
  /** Keep the last notebook cell available while the sidebar opens the palette. */
  function recordFocus(event: React.FocusEvent<HTMLElement>) {
    const row = event.target.closest<HTMLElement>('[data-cell-id]')
    const id = row?.dataset.cellId ?? null
    setSelected(id)
    if (!id) {
      setEditingId(null)
      setViewing(null)
      setCellMode('idle')
      return
    }
    if (row === event.target) {
      setEditingId(null)
      setViewing(null)
      setCellMode('selection')
    } else if (event.target.closest('math-field, textarea, [contenteditable="true"]')) {
      setCellMode('editing')
    } else {
      setViewing(id)
      setCellMode('view')
    }
  }
  /** Dispatch a palette choice against the last focused notebook cell. */
  function paletteCommand(command: string) {
    return runCellCommand(command, selectedId)
  }
  /** Expose the same dispatcher used by shortcuts to the route's command palette. */
  function bindPalette() {
    /** Read actual focus so selection shortcuts do not consume arrows in the sidebar or menus. */
    function getContext(): CommandContext {
      const target = document.activeElement
      const notebookFocus = !!target && !!notebookRef.current?.contains(target)
      const cellFocus = notebookFocus && selectedId !== null
      /** Identify the current cell kind without reading its source. */
      function matches(cell: Pick<NotebookCell, 'cellId'>) {
        return cell.cellId === selectedId
      }
      return { cellMode, notebookFocus, cellFocus, mathFocus: cellFocus && page?.cells.find(matches)?.kind === 'math' }
    }
    return { run: paletteCommand, getContext }
  }
  useImperativeHandle(commandRef, bindPalette)

  /** Rename the open page. */
  function rename(title: string) {
    renamePage(pageId, title)
  }
  /** Apply the selected display settings. */
  function setMetadata(pageMetadata: PageMetadata) {
    /** Copy the display settings onto the latest page. */
    function update(current: Page) {
      return { ...current, pageMetadata }
    }
    updatePage(pageId, update)
  }
  /** Append a math cell. */
  function addMath() {
    const cellId = createCellId()
    /** Allocate a math cell on the latest page. */
    function update(current: Page) {
      return appendCell(current, 'math', cellId)
    }
    updatePage(pageId, update)
    setEditing(cellId)
  }
  /** Append a Markdown cell. */
  function addMarkdown() {
    const cellId = createCellId()
    /** Allocate a Markdown cell on the latest page. */
    function update(current: Page) {
      return appendCell(current, 'markdown', cellId)
    }
    updatePage(pageId, update)
    setEditing(cellId)
  }
  /** Subscribe each cell by its position and stable identity. */
  function renderSlot(slot: Pick<NotebookCell, 'cellId'>, index: number) {
    return (
      <NotebookCellEditor
        editorMode={page?.pageMetadata.editorMode ?? 'rich'}
        focused={slot.cellId === viewingId}
        selected={slot.cellId === selectedId}
        editing={slot.cellId === editingId}
        setEditing={setEditing}
        onEditGraph={onEditGraph}
        key={slot.cellId}
        pageId={pageId}
        cellId={slot.cellId}
        index={index}
      />
    )
  }
  /** Render preorder cells as nested groups while preserving each editor's absolute index and stable id. */
  function renderBlocks(start: number, end: number): React.ReactNode {
    if (!page) return null
    const blocks: React.ReactNode[] = []
    const draggedIndex = draggedId ? blockIndex(page.cells, draggedId) : -1
    const draggedEnd = draggedIndex >= 0 ? blockEnd(page.cells, draggedIndex) : -1
    for (let index = start; index < end;) {
      const slot = page.cells[index]
      const next = blockEnd(page.cells, index)
      blocks.push(
        <NotebookBlockView
          key={slot.cellId}
          cellId={slot.cellId}
          index={index}
          cells={page.cells}
          descendantCount={next - index - 1}
          content={renderSlot(slot, index)}
          draggedId={draggedId}
          blocked={index >= draggedIndex && index < draggedEnd}
          onDrag={setDraggedId}
          onMove={relocateBlock}
          onAction={blockAction}
        >
          {renderBlocks(index + 1, next)}
        </NotebookBlockView>,
      )
      index = next
    }
    return blocks
  }
  if (!page) return null
  return (
    <main ref={notebookRef} tabIndex={-1} data-cell-mode={cellMode} onCopy={handleCellCopy} onPaste={handleCellPaste} onFocusCapture={recordFocus} className={`notebook notebook-${page.pageMetadata.width}`} aria-label="Folio notebook">
      <span className="notebook-announcement" role="status">
        {notice}
      </span>
      <Dialog.Root open={focusPickerOpen} onOpenChange={setFocusPickerOpen} onOpenChangeComplete={finishFocusPicker}>
        <Dialog.Portal>
          <Dialog.Backdrop className="focus-cell-backdrop" />
          <Dialog.Popup className="focus-cell-dialog" finalFocus={false}>
            <Dialog.Title className="focus-cell-title">Focus a cell</Dialog.Title>
            <form onSubmit={focusNumberedCell}>
              <TextField label="Cell number" name="position" type="number" min={1} max={page.cells.length} required defaultValue={1} />
              <Button type="submit">Focus</Button>
              <Dialog.Close className="ui-button ui-button-quiet">Cancel</Dialog.Close>
            </form>
          </Dialog.Popup>
        </Dialog.Portal>
      </Dialog.Root>
      <PageFrame page={page} interaction="editable" onAddMathCell={addMath} onAddMarkdownCell={addMarkdown} onOpenGraph={onOpenGraph} onTitleChange={rename} onPageMetadataChange={setMetadata} content={renderBlocks(0, page.cells.length)} />
    </main>
  )
}
