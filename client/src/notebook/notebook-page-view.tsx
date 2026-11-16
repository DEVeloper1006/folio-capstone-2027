/**
 * Render the open notebook page from query subscriptions, track cell selection and editing, and run page and cell commands.
 *
 * @file
 */
import { useImperativeHandle, useRef, useState } from 'react'
import type { ClipboardEvent, Ref } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { PageFrame } from '#/components/page-view'
import { CellFrame } from '#/component-library/cell-frame'
import { MathIcon, MarkdownIcon } from '#/component-library/icons/folio-icons'
import { LatexCell } from '#/components/latex-cell'
import { MarkdownCell } from '#/components/markdown-cell'
import { appendCell, editCell, notebookCommands, usePageSelection } from './use-page-state'
import { createCellId, pastedLatex } from './notebook-cells'
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
function pageLayout(page: Page): Omit<Page, 'cells'> & { cells: readonly Pick<NotebookCell, 'kind' | 'cellId'>[] } {
  /** Keep each cell's identity and kind for ordering and the add-cell control. */
  function cellSlot({ cellId, kind }: NotebookCell) {
    return { cellId, kind }
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
  selectRow,
  setEditing,
}: {
  editorMode: CellEditorMode
  pageId: string
  index: number
  cellId: string
  editing: boolean
  focused: boolean
  selected: boolean
  selectRow: (id: string) => void
  setEditing: (id: string | null) => void
}) {
  const client = useQueryClient()
  /** Ignore a stale slot while the layout is changing. */
  function selectCell(page: Page) {
    const cell = page.cells.at(index)
    return cell?.cellId === cellId ? cell : undefined
  }
  const cell = usePageSelection(pageId, selectCell)
  /** Store the edited source on the page containing this field. */
  function changeSource(id: string, source: string) {
    /** Apply the edit to the latest document. */
    function update(page: Page) {
      return editCell(page, id, source)
    }
    notebookCommands(client).updatePage(pageId, update)
  }
  /** Activate this cell through its normal edit control. */
  function beginEditing() {
    setEditing(cellId)
  }
  /** Finish or begin editing the current Markdown cell. */
  function changeEditing(value: boolean) {
    setEditing(value ? cellId : null)
  }
  /** Focus the frame to select this whole cell. */
  function selectFromGutter() {
    selectRow(cellId)
  }
  if (!cell) return null
  return (
    <CellFrame
      state={editing ? 'editing' : focused ? 'focused' : selected ? 'selected' : 'unselected'}
      icon={cell.kind === 'math' ? <MathIcon /> : <MarkdownIcon />}
      label={`Select cell ${index + 1}`}
      role="group"
      tabIndex={0}
      aria-label={`${cell.kind === 'math' ? 'Math' : 'Markdown'} cell ${index + 1}`}
      data-cell-id={cellId}
      onSelect={selectFromGutter}
    >
      {cell.kind === 'math' ? (
        <LatexCell editorMode={editorMode} cellId={cellId} editing={editing} onBeginEditing={beginEditing} initialLatex={cell.latex} onLatexChange={changeSource} />
      ) : (
        <MarkdownCell editorMode={editorMode} cellId={cellId} editing={editing} onEditingChange={changeEditing} markdown={cell.markdown} onMarkdownChange={changeSource} />
      )}
    </CellFrame>
  )
}

/** Render a cached page. Only layout changes update the frame and only the edited cell receives new source. */
export function NotebookPageView({ pageId, commandRef }: { pageId: string; commandRef: Ref<NotebookCommandController> }) {
  const client = useQueryClient()
  const page = usePageSelection(pageId, pageLayout)
  const { updatePage, renamePage, getPage } = notebookCommands(client)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [cellMode, setCellMode] = useState<CommandContext['cellMode']>('idle')
  /** Enter edit mode for a cell, or return to cell selection when editing finishes. */
  function setEditing(id: string | null) {
    setEditingId(id)
    setCellMode(id ? 'editing' : 'selection')
    if (id) setSelected(id)
  }
  const notebookRef = useRef<HTMLElement>(null)
  const [viewingId, setViewing] = useState<string | null>(null)
  const [selectedId, setSelected] = useState<string | null>(null)
  const [notice, setNotice] = useState('')
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
      await navigator.clipboard.writeText(cell.kind === 'math' ? cell.latex : cell.markdown)
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
      return editCell(current, id, cell?.kind === 'math' ? pastedLatex(text) : text)
    }
    updatePage(pageId, replace)
    setNotice('Cell contents pasted')
  }
  /** Read clipboard text for a palette action or a custom paste shortcut. */
  async function pasteCell(id: string) {
    try {
      pasteSource(id, await navigator.clipboard.readText())
    } catch {
      setNotice('Clipboard unavailable. Use Cmd/Ctrl+V on the selected cell.')
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
    event.clipboardData.setData('text/plain', cell.kind === 'math' ? cell.latex : cell.markdown)
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
    const math = getPage(pageId)?.cells.find(matches)?.kind === 'math'
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
        const position = Number(window.prompt('Cell number (1–' + cells.length + ')'))
        const slot = Number.isInteger(position) && position > 0 ? cells.at(position - 1) : undefined
        if (!slot) return false
        setEditing(slot.cellId)
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
      /** Remove only the selected cell from the latest page. */
      function remove(current: Page) {
        /** Keep cells with other ids. */
        function keep(cell: NotebookCell) {
          return cell.cellId !== id
        }
        return { ...current, cells: current.cells.filter(keep) }
      }
      updatePage(pageId, remove)
      selectRow(cells.at(index + 1)?.cellId ?? (index > 0 ? cells[index - 1].cellId : undefined))
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
      const cell: NotebookCell = original.kind === 'math' ? { cellId, kind: 'math', latex: duplicate ? original.latex : '' } : { cellId, kind: 'markdown', markdown: '' }
      const nextCells = [...current.cells]
      nextCells.splice(command.endsWith('createAbove') ? sourceIndex : sourceIndex + 1, 0, cell)
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
    if (row === event.target || event.target.closest('.notebook-cell-gutter')) {
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
        selectRow={selectRow}
        selected={slot.cellId === selectedId}
        editing={slot.cellId === editingId}
        setEditing={setEditing}
        key={slot.cellId}
        pageId={pageId}
        cellId={slot.cellId}
        index={index}
      />
    )
  }
  if (!page) return null
  return (
    <main ref={notebookRef} tabIndex={-1} data-cell-mode={cellMode} onCopy={handleCellCopy} onPaste={handleCellPaste} onFocusCapture={recordFocus} className={`notebook notebook-${page.pageMetadata.width}`} aria-label="Folio notebook">
      <span className="cell-command-notice" role="status">
        {notice}
      </span>
      <PageFrame page={page} interaction="editable" onAddMathCell={addMath} onAddMarkdownCell={addMarkdown} onTitleChange={rename} onPageMetadataChange={setMetadata} content={page.cells.map(renderSlot)} />
    </main>
  )
}
