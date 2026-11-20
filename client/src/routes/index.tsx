/**
 * Display the notebook at the home route with its page list, optional graph editing panel, settings, and command palette. Graph figures remain part of the document rather than a separate workspace view.
 *
 * @file
 */

import { useQueryClient } from '@tanstack/react-query'
import { useEffect, useRef, useState } from 'react'
import { createFileRoute } from '@tanstack/react-router'
import { CommandPaletteView } from '#/components/command-palette-view.tsx'
import type { CommandPaletteAction } from '#/components/command-palette-view.tsx'
import { SettingsEditor } from '#/settings/settings-editor'
import type { SettingsCategory } from '#/settings/settings-editor'
import { useSettings } from '#/settings/use-settings'
import { PageSidebarView } from '#/components/page-sidebar-view'
import type { NotebookCommandController } from '#/notebook/notebook-page-view'
import { NotebookPageView } from '#/notebook/notebook-page-view'
import { shortcutLabel } from '#/editor/commands/shortcut-overrides'
import { workspaceCommandForKey } from '#/editor/commands/editor-commands.ts'
import { useEditorCommandShortcuts } from '#/editor/commands/use-editor-command-shortcuts.ts'
import { notebookCommands, usePageList } from '#/notebook/use-page-state.tsx'
import { MathHelpPanel } from '#/math-help/math-help-panel'
import { GraphWorkspace } from '#/graph/graph-workspace'
import { Button } from '#/component-library'
import type { HeadingTarget, PageHeading } from '#/notebook/notebook-outline'
import { folderPath } from '#/notebook/notebook-folders'
import { ArrowLeft, FolderOpen } from 'lucide-react'
import './workspace.css'
import { NotebookRoots } from '#/notebook/notebook-roots'
import { NotebookExport } from '#/notebook/notebook-export'
import type { Page } from '#/notebook/page'

export const Route = createFileRoute('/')({ component: NotebookPage })

/** Show the notebook, settings and palette. Subscribe the sidebar to page titles and selection. */
function NotebookPage() {
  const { pages, folders = [], openPageId, roots } = usePageList()
  const commands = notebookCommands(useQueryClient())
  const { selectPage: showPage, createPage, renamePage, deletePage } = commands
  const [rootsOpen, setRootsOpen] = useState(false)
  const [rootsError, setRootsError] = useState('')
  const [exportPage, setExportPage] = useState<Page>()
  const [headingTarget, setHeadingTarget] = useState<HeadingTarget>()
  const { overrides, actions } = useEditorCommandShortcuts()
  const config = useSettings()
  const sidebarCommand = useRef<((id: string) => boolean) | null>(null)
  const cellCommand = useRef<NotebookCommandController | null>(null)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [settingsCategory, setSettingsCategory] = useState<SettingsCategory>('appearance')
  const paletteOrigin = useRef<HTMLElement | null>(null)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [hintRequest, setHintRequest] = useState(0)
  const [activeCellId, setActiveCellId] = useState<string>()
  const [graphOpen, setGraphOpen] = useState(false)
  const [graphCellId, setGraphCellId] = useState<string | undefined>()

  /** Leave the shortcut list and show the requested page. */
  function selectPage(pageId: string) {
    setSettingsOpen(false)
    closeGraph()
    setActiveCellId(undefined)
    showPage(pageId)
    setHeadingTarget(undefined)
  }

  /** Leave the shortcut list, then add an empty page and show it. */
  function createAndShowPage(folderId?: string) {
    setSettingsOpen(false)
    closeGraph()
    setActiveCellId(undefined)
    createPage(folderId)
  }

  /** Open the requested page and address its heading by cell and occurrence. */
  function navigateHeading(pageId: string, heading: PageHeading) {
    selectPage(pageId)
    setHeadingTarget({ ...heading, pageId, request: Date.now() })
  }
  /** Manage the current Markdown folder and portable backups. */
  function openRoots() {
    setRootsOpen(true)
  }
  /** Return to the notebook after folder management. */
  function closeRoots() {
    setRootsOpen(false)
  }
  /** Reload external edits when the desktop window regains focus. */
  function watchRoots() {
    /** Apply completed external edits when the app regains focus. */
    function refresh() {
      try {
        commands.reloadRoots()
        setRootsError('')
      } catch (error) {
        setRootsError(error instanceof Error ? error.message : String(error))
      }
    }
    window.addEventListener('focus', refresh)
    /** Release the active root's focus listener. */
    function stop() {
      window.removeEventListener('focus', refresh)
    }
    return stop
  }
  useEffect(watchRoots, [])
  /** Freeze the latest saved page while the export picker is open. */
  function openExport() {
    const page = commands.getPage(openPageId)
    if (page) setExportPage(structuredClone(page))
  }
  /** Return to the original page after export. */
  function closeExport() {
    setExportPage(undefined)
  }
  /** Open the graphical preferences in place of the page. */
  function openSettings() {
    setSettingsCategory('appearance')
    setSettingsOpen(true)
  }

  /** Open the appearance controls from the existing theme command. */
  function openThemes() {
    setSettingsCategory('appearance')
    setSettingsOpen(true)
  }
  /** Open the editable keyboard shortcuts directly from the command palette. */
  function openShortcuts() {
    setSettingsCategory('shortcuts')
    setSettingsOpen(true)
  }
  /** Show the current page's saved graph workspace without changing its cells. */
  function openGraph() {
    setSettingsOpen(false)
    setGraphCellId(undefined)
    setGraphOpen(true)
  }
  /** Reopen a document figure in the same panel with its own source and view. */
  function editGraph(cellId: string) {
    setSettingsOpen(false)
    setGraphCellId(cellId)
    setGraphOpen(true)
  }
  /** Close the tool panel without replacing the document view. */
  function closeGraph() {
    setGraphOpen(false)
    setGraphCellId(undefined)
  }
  /** Request a hint in the active notebook block through the existing keyboard command. */
  function openHelp() {
    setSettingsOpen(false)
    /** Issue a new request without creating a separate help surface. */
    function increment(value: number) {
      return value + 1
    }
    setHintRequest(increment)
  }
  /** Return to notebook editing, preserving graph expressions and slider settings. */
  function openNotebook() {
    setSettingsOpen(false)
  }
  /** Show the command palette over the page or the shortcut list. */
  function openCommandPalette() {
    paletteOrigin.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    setPaletteOpen(true)
  }

  /** Hide the command palette without choosing a command. */
  function closeCommandPalette() {
    setPaletteOpen(false)
    paletteOrigin.current?.focus({ preventScroll: true })
  }

  /** Run workspace commands from either a shortcut or the palette. */
  function dispatch(id: string) {
    if (id === 'workspace.command.open') {
      openCommandPalette()
      return true
    }
    if (id === 'workspace.settings.theme') {
      openThemes()
      return true
    }
    if (id === 'workspace.settings.shortcuts') {
      openShortcuts()
      return true
    }
    if (id === 'workspace.settings.open') {
      openSettings()
      return true
    }
    if (id === 'workspace.math.help') {
      openHelp()
      return true
    }
    if (id === 'workspace.graph.close') {
      closeGraph()
      return true
    }
    if (id === 'workspace.graph.open') {
      openGraph()
      return true
    }
    if (id.startsWith('open-page:')) {
      selectPage(id.slice('open-page:'.length))
      return true
    }
    if (id.startsWith('workspace.currentPage.cell.') && settingsOpen) return false
    return sidebarCommand.current?.(id) || cellCommand.current?.run(id) || false
  }
  /** Run a chosen command after dismissing the palette. */
  function runCommand(action: CommandPaletteAction) {
    setPaletteOpen(false)
    dispatch(action.id)
  }
  /** Listen at the document so the palette shortcut works before any page control has focus. */
  function listenForWorkspaceKeys() {
    /** Scope cell shortcuts to cell elements and let dialogs and shortcut recording own their input. */
    function handleKey(event: KeyboardEvent) {
      if (event.isComposing || event.defaultPrevented || paletteOpen || document.querySelector('.command-settings-shortcut.is-recording')) return
      const target = event.target
      const command = workspaceCommandForKey(event, overrides, cellCommand.current?.getContext() ?? { cellMode: 'idle', notebookFocus: false, cellFocus: false, mathFocus: false })
      if (!command || !(target instanceof Element)) return
      if (target.closest('.notebook-block-tools') && command.id !== 'workspace.command.open' && command.id !== 'workspace.settings.open') return
      if ((command.when === 'cellFocus' || command.when === 'mathFocus') && !target.closest('[data-cell-id]')) return
      if (command.id.endsWith('.duplicateBelow') && target.closest('.markdown-cell')) {
        event.preventDefault()
        event.stopImmediatePropagation()
        return
      }
      if (target.closest('.command-menu,.latex-editor-inline') && command.id !== 'workspace.command.open' && command.id !== 'workspace.settings.open') return
      if (target.closest('input,textarea,[contenteditable=true]') && !target.closest('[data-cell-id]') && command.id !== 'workspace.command.open' && command.id !== 'workspace.settings.open') return
      if (event.repeat && !command.id.endsWith('.selectNext') && !command.id.endsWith('.selectPrevious')) {
        event.preventDefault()
        event.stopImmediatePropagation()
        return
      }
      // Default copy and paste use native clipboard events with clipboard data attached.
      if ((command.id === 'workspace.currentPage.cell.pasteSelected' || command.id === 'workspace.currentPage.cell.copySelected') && !Object.hasOwn(overrides, command.id)) return
      if (!dispatch(command.id)) return
      event.preventDefault()
      event.stopImmediatePropagation()
    }
    document.addEventListener('keydown', handleKey, true)
    /** Detach the listener with its current page and bindings. */
    function detach() {
      document.removeEventListener('keydown', handleKey, true)
    }
    return detach
  }
  useEffect(listenForWorkspaceKeys)
  /** Expose each sidebar page in the palette. */
  function openPageAction(page: (typeof pages)[number]) {
    return { id: 'open-page:' + page.pageId, label: page.title || 'Untitled', keywords: ['page', 'open', folderPath(folders, page.folderId)] }
  }
  /** Match the active title without subscribing to cell edits. */
  function isCurrentPage(page: (typeof pages)[number]) {
    return page.pageId === openPageId
  }
  /** Keep hidden notebook actions out of the search results. */
  function isAvailableAction(action: CommandPaletteAction) {
    return !action.id.startsWith('workspace.currentPage.cell.') || !settingsOpen
  }
  const pageTitle = pages.find(isCurrentPage)?.title || 'Untitled'
  const viewActions = [
    { id: 'workspace.graph.open', label: 'Open graph panel', keywords: ['plot', 'insert'] },
    { id: 'workspace.graph.close', label: 'Close graph panel', keywords: ['plot'] },
  ]

  return (
    <div className="notebook-shell" data-status-bar={!settingsOpen}>
      <PageSidebarView
        commandRef={sidebarCommand}
        pages={pages}
        folders={folders}
        folderCommands={commands}
        onNavigateHeading={navigateHeading}
        openPageId={openPageId}
        settingsOpen={!!settingsOpen}
        commandShortcut={shortcutLabel('workspace.command.open', '⌘K', overrides) ?? ''}
        onSelectPage={selectPage}
        onCreatePage={createAndShowPage}
        onRenamePage={renamePage}
        onDeletePage={deletePage}
        onOpenSettings={openSettings}
        onOpenCommandPalette={openCommandPalette}
      />
      <div className="notebook-main">
        <header className="workspace-toolbar">
          <div className="workspace-location">
            <Button variant="icon" onClick={openRoots} aria-label="Manage Roots" title="Manage Roots">
              <FolderOpen size={16} aria-hidden="true" />
            </Button>
            <span>{settingsOpen ? 'Settings' : `${folderPath(folders, pages.find(isCurrentPage)?.folderId)} / ${pageTitle}`}</span>
          </div>
          {!settingsOpen && (
            <Button variant="quiet" onClick={openExport}>
              Export
            </Button>
          )}
          {settingsOpen && (
            <Button variant="quiet" onClick={openNotebook}>
              <ArrowLeft size={15} aria-hidden="true" />
              Back to page
            </Button>
          )}
        </header>
        {(roots.error || rootsError) && (
          <div role="alert" className="settings-status">
            {roots.error || rootsError}
            <Button onClick={openRoots}>Open Roots</Button>
          </div>
        )}
        {config.document.error && (
          <div role="alert" className="settings-status">
            Settings were not applied: {config.document.error}{' '}
            <Button variant="quiet" onClick={openSettings}>
              Edit settings
            </Button>
          </div>
        )}
        <div hidden={!settingsOpen}>
          <SettingsEditor document={config.document} settings={config.settings} save={config.save} reload={config.reload} active={settingsOpen} category={settingsCategory} onCategoryChange={setSettingsCategory} paletteOpen={paletteOpen} onOpenCommandPalette={openCommandPalette} />
        </div>
        {!settingsOpen && (
          <div className="workspace-panels" data-graph-open={graphOpen}>
            <div className="workspace-notes">
              <NotebookPageView headingTarget={headingTarget} commandRef={cellCommand} key={openPageId} pageId={openPageId} onOpenGraph={openGraph} onEditGraph={editGraph} onActiveCellChange={setActiveCellId} />
            </div>
            {graphOpen && (
              <div className="workspace-graph">
                <GraphWorkspace key={`${openPageId}:${graphCellId ?? 'scratch'}`} pageId={openPageId} cellId={graphCellId} onClose={closeGraph} />
              </div>
            )}
          </div>
        )}
      </div>
      {!settingsOpen && <MathHelpPanel key={openPageId} pageId={openPageId} cellId={activeCellId} preferences={config.settings.math} hintRequest={hintRequest} />}
      {rootsOpen && <NotebookRoots path={roots.path} onReload={commands.reloadRoots} onClose={closeRoots} />}
      {exportPage && <NotebookExport page={exportPage} onClose={closeExport} />}
      <CommandPaletteView actions={[...pages.map(openPageAction), ...viewActions, ...actions.filter(isAvailableAction)]} open={paletteOpen} onClose={closeCommandPalette} onRun={runCommand} />
    </div>
  )
}
