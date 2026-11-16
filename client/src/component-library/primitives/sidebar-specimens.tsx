/**
 * Show the page sidebar beside a view-only page or the keyboard-shortcut list. Creating, renaming, and recording shortcut labels here stays in this specimen. It does not change the notebook's pages.
 *
 * @file
 */

import { useState } from 'react'
import { CommandPaletteView } from '#/components/command-palette-view.tsx'
import type { CommandPaletteAction } from '#/components/command-palette-view.tsx'
import { CommandSettingsView } from '#/components/command-settings-view.tsx'
import { PageSidebarView } from '#/components/page-sidebar-view.tsx'
import { ThemeControls } from '#/theme/theme-controls'
import { PageView } from '#/components/page-view.tsx'
import { useEditorCommandShortcuts } from '#/editor/commands/use-editor-command-shortcuts.ts'
import { createEmptyPage, defaultPageMetadata, nextUntitledTitle } from '#/notebook/page.ts'
import type { Page } from '#/notebook/page.ts'

const galleryPages: readonly Page[] = [
  {
    pageId: 'gallery-notes',
    title: 'Working notes',
    cells: [{ cellId: 'gallery-note', kind: 'markdown', markdown: 'A short note kept with this page.' }],
    pageMetadata: { ...defaultPageMetadata },
  },
  {
    pageId: 'gallery-problem',
    title: 'Problem set',
    cells: [{ cellId: 'gallery-math', kind: 'math', latex: 'x^2' }],
    pageMetadata: { ...defaultPageMetadata },
  },
]

/** Let the gallery create, rename, and switch sample pages, and show the open one without editing its cells. */
export function PageSidebarSpecimen() {
  const [pages, setPages] = useState(galleryPages)
  const [openPageId, setOpenPageId] = useState(galleryPages[0].pageId)
  const { overrides, actions, setShortcut, resetShortcut } = useEditorCommandShortcuts()
  const [settingsOpen, setSettingsOpen] = useState<'theme' | 'shortcuts' | null>(null)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [lastCommandLabel, setLastCommandLabel] = useState<string | undefined>(undefined)

  /** Leave the shortcut list and show the requested sample page. */
  function selectPage(pageId: string) {
    setSettingsOpen(null)
    setOpenPageId(pageId)
  }

  /** Leave the shortcut list, then append an empty sample page and show it. */
  function createPage() {
    const page = createEmptyPage(nextUntitledTitle(pages))
    /** Keep the pages already in this specimen and add the new one. */
    function appendPage(current: readonly Page[]) {
      return [...current, page]
    }
    setPages(appendPage)
    setSettingsOpen(null)
    setOpenPageId(page.pageId)
  }

  /** Remove one sample page. The last page stays, and deleting the open page shows a neighbor. */
  function deletePage(pageId: string) {
    if (pages.length < 2) return
    /** Match the page to remove. */
    function isTarget(page: Page) {
      return page.pageId === pageId
    }
    const removedIndex = pages.findIndex(isTarget)
    if (removedIndex < 0) return
    /** Keep every sample page except the one that was removed. */
    function isKept(page: Page) {
      return page.pageId !== pageId
    }
    const remaining = pages.filter(isKept)
    setPages(remaining)
    if (openPageId !== pageId) return
    setSettingsOpen(null)
    const nextIndex = Math.min(removedIndex, remaining.length - 1)
    setOpenPageId(remaining[nextIndex].pageId)
  }

  /** Replace one sample page's title. */
  function renamePage(pageId: string, title: string) {
    /** Write the title onto the matching sample page. */
    function renameMatchingPage(current: readonly Page[]) {
      /** Replace the title only for the requested page. */
      function updatePage(page: Page): Page {
        if (page.pageId !== pageId) return page
        return { ...page, title }
      }
      return current.map(updatePage)
    }
    setPages(renameMatchingPage)
  }

  /** Match the page currently shown beside the list. */
  function isOpen(page: Page) {
    return page.pageId === openPageId
  }
  const openPage = pages.find(isOpen) ?? pages[0]

  /** Show the keyboard shortcut list in place of the sample page. */
  function openSettings() {
    setSettingsOpen('shortcuts')
  }

  /** Show the same theme preferences as the notebook. */
  function openThemes() {
    setSettingsOpen('theme')
  }
  /** Show the command palette over this specimen. */
  function openCommandPalette() {
    setPaletteOpen(true)
  }

  /** Hide the command palette without choosing a command. */
  function closeCommandPalette() {
    setPaletteOpen(false)
  }

  /** Remember the chosen command's label and close the palette. The sample page stays unchanged. */
  function runCommand(action: CommandPaletteAction) {
    setLastCommandLabel(action.label)
    setPaletteOpen(false)
  }

  return (
    <div className="sidebar-specimen">
      <PageSidebarView pages={pages} openPageId={openPageId} settingsOpen={!!settingsOpen} onOpenThemes={openThemes} onSelectPage={selectPage} onCreatePage={createPage} onRenamePage={renamePage} onDeletePage={deletePage} onOpenSettings={openSettings} onOpenCommandPalette={openCommandPalette} />
      <div className="sidebar-specimen-page">
        {settingsOpen === 'theme' ? (
          <ThemeControls />
        ) : settingsOpen ? (
          <CommandSettingsView overrides={overrides} paletteOpen={paletteOpen} lastCommandLabel={lastCommandLabel} onShortcutChange={setShortcut} onResetShortcut={resetShortcut} onOpenCommandPalette={openCommandPalette} />
        ) : (
          <PageView interaction="view" page={openPage} />
        )}
      </div>
      <CommandPaletteView actions={actions} open={paletteOpen} onClose={closeCommandPalette} onRun={runCommand} />
    </div>
  )
}
