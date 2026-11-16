/**
 * Display the mixed math and Markdown notebook at the home route. Contains the notebook state provider and the shell that shows the page list beside the open page, the keyboard-shortcut list, or the command palette.
 *
 * @file
 */

import { useQueryClient } from '@tanstack/react-query'
import { useEffect, useRef, useState } from 'react'
import { createFileRoute } from '@tanstack/react-router'
import { CommandPaletteView } from '#/components/command-palette-view.tsx'
import type { CommandPaletteAction } from '#/components/command-palette-view.tsx'
import { CommandSettingsView } from '#/components/command-settings-view.tsx'
import { PageSidebarView } from '#/components/page-sidebar-view'
import type { NotebookCommandController } from '#/notebook/notebook-page-view'
import { NotebookPageView } from '#/notebook/notebook-page-view'
import { ThemeControls } from '#/theme/theme-controls'
import { workspaceCommandForKey } from '#/editor/commands/editor-commands.ts'
import { useEditorCommandShortcuts } from '#/editor/commands/use-editor-command-shortcuts.ts'
import { notebookCommands, usePageList } from '#/notebook/use-page-state.tsx'

export const Route = createFileRoute('/')({ component: NotebookPage })

/** Show the notebook, settings and palette. Subscribe the sidebar to page titles and selection. */
function NotebookPage() {
  const { pages, openPageId } = usePageList()
  const { selectPage: showPage, createPage, renamePage, deletePage } = notebookCommands(useQueryClient())
  const { overrides, actions, setShortcut, resetShortcut } = useEditorCommandShortcuts()
  const sidebarCommand = useRef<((id: string) => boolean) | null>(null)
  const cellCommand = useRef<NotebookCommandController | null>(null)
  const [settingsOpen, setSettingsOpen] = useState<'shortcuts' | 'theme' | null>(null)
  const paletteOrigin = useRef<HTMLElement | null>(null)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [lastCommandLabel, setLastCommandLabel] = useState<string | undefined>(undefined)

  /** Leave the shortcut list and show the requested page. */
  function selectPage(pageId: string) {
    setSettingsOpen(null)
    showPage(pageId)
  }

  /** Leave the shortcut list, then add an empty page and show it. */
  function createAndShowPage() {
    setSettingsOpen(null)
    createPage()
  }

  /** Show the keyboard shortcut list in place of the page. */
  function openSettings() {
    setSettingsOpen('shortcuts')
  }

  /** Open the shared palette and color-mode picker. */
  function openThemes() {
    setSettingsOpen('theme')
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
      openSettings()
      return true
    }
    if (id.startsWith('open-page:')) {
      selectPage(id.slice('open-page:'.length))
      return true
    }
    return sidebarCommand.current?.(id) || cellCommand.current?.run(id) || false
  }
  /** Run a chosen command after dismissing the palette. */
  function runCommand(action: CommandPaletteAction) {
    setPaletteOpen(false)
    if (dispatch(action.id)) setLastCommandLabel(action.label)
  }
  /** Listen at the document so the palette shortcut works before any page control has focus. */
  function listenForWorkspaceKeys() {
    /** Scope cell shortcuts to cell elements and let dialogs and shortcut recording own their input. */
    function handleKey(event: KeyboardEvent) {
      if (event.isComposing || event.defaultPrevented || paletteOpen || document.querySelector('.command-settings-shortcut.is-recording')) return
      const target = event.target
      const command = workspaceCommandForKey(event, overrides, cellCommand.current?.getContext() ?? { cellMode: 'idle', notebookFocus: false, cellFocus: false, mathFocus: false })
      if (!command || !(target instanceof Element)) return
      if ((command.when === 'cellFocus' || command.when === 'mathFocus') && !target.closest('[data-cell-id]')) return
      if (command.id.endsWith('.duplicateBelow') && target.closest('.markdown-cell')) {
        event.preventDefault()
        event.stopImmediatePropagation()
        return
      }
      if (target.closest('.command-menu,.latex-editor-inline') && command.id !== 'workspace.command.open') return
      if (target.closest('input,textarea,[contenteditable=true]') && !target.closest('[data-cell-id]') && command.id !== 'workspace.command.open') return
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
    return { id: 'open-page:' + page.pageId, label: 'Open page: ' + (page.title || 'Untitled') }
  }

  return (
    <div className="notebook-shell">
      <PageSidebarView
        commandRef={sidebarCommand}
        pages={pages}
        openPageId={openPageId}
        settingsOpen={!!settingsOpen}
        onOpenThemes={openThemes}
        onSelectPage={selectPage}
        onCreatePage={createAndShowPage}
        onRenamePage={renamePage}
        onDeletePage={deletePage}
        onOpenSettings={openSettings}
        onOpenCommandPalette={openCommandPalette}
      />
      <div className="notebook-main">
        {settingsOpen ? (
          <main className="notebook notebook-full" aria-label={settingsOpen === 'theme' ? 'Theme settings' : 'Keyboard shortcuts'}>
            {settingsOpen === 'theme' ? <ThemeControls /> : <CommandSettingsView overrides={overrides} paletteOpen={paletteOpen} lastCommandLabel={lastCommandLabel} onShortcutChange={setShortcut} onResetShortcut={resetShortcut} onOpenCommandPalette={openCommandPalette} />}
          </main>
        ) : (
          <NotebookPageView commandRef={cellCommand} key={openPageId} pageId={openPageId} />
        )}
      </div>
      <CommandPaletteView actions={[...actions, ...pages.map(openPageAction)]} open={paletteOpen} onClose={closeCommandPalette} onRun={runCommand} />
    </div>
  )
}
