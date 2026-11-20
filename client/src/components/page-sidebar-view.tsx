/**
 * Render Folio's page navigation with visible search and new-page actions, page menus, resizing, and settings. New pages focus their document title; existing pages can be renamed in the sidebar. This view does not store page contents.
 *
 * @file
 */

import { useEffect, useImperativeHandle, useRef, useState } from 'react'
import type { ChangeEvent, CSSProperties, KeyboardEvent, PointerEvent as ReactPointerEvent } from 'react'
import { ContextMenu } from '@base-ui/react/context-menu'
import { Menu } from '@base-ui/react/menu'
import { Tooltip } from '@base-ui/react/tooltip'
import { CellEditingIcon, DeleteIcon, GearIcon, KeyboardIcon, MoreActionsIcon, PageIcon, PlusIcon, SearchIcon, SidebarCollapseIcon, SidebarExpandIcon, SidebarShowIcon } from '#/component-library/icons/folio-icons.tsx'
import { IconTooltip } from '#/component-library/primitives/icon-tooltip.tsx'
import type { PageSummary, NotebookFolder } from '#/state/global-states'
import { ChevronRight, Folder, FolderOpen, FolderPlus } from 'lucide-react'
import { NotebookOutlineView } from '#/notebook/notebook-outline-view'
import type { PageHeading } from '#/notebook/notebook-outline'
import { NotebookFolderDialog } from '#/notebook/notebook-folder-dialog'
import type { FolderAction, FolderActions } from '#/notebook/notebook-folder-dialog'
import { folderAncestors } from '#/notebook/notebook-folders'
import './page-tree.css'

/** The page list is open, reduced to icons, or fully hidden. */
type SidebarMode = 'open' | 'collapsed' | 'hidden'

const defaultSidebarWidth = 240
const minSidebarWidth = 220
const maxSidebarWidth = 440

/** Keep a dragged page-list width between the narrowest useful column and the widest column that still leaves the page readable. */
function clampSidebarWidth(width: number) {
  return Math.min(maxSidebarWidth, Math.max(minSidebarWidth, width))
}

/** Receive the pages to list, whether keyboard shortcuts are on screen, and the callbacks that select, create, rename, or delete a page or open a settings destination. */
interface PageSidebarViewProps {
  commandRef?: React.Ref<(id: string) => boolean>
  pages: readonly PageSummary[]
  folders?: readonly NotebookFolder[]
  folderCommands?: FolderActions
  onNavigateHeading?: (pageId: string, heading: PageHeading) => void
  openPageId: string
  settingsOpen: boolean
  commandShortcut?: string
  onSelectPage: (pageId: string) => void
  onCreatePage: (folderId?: string) => void
  onRenamePage: (pageId: string, title: string) => void
  onDeletePage: (pageId: string) => void
  onOpenThemes?: () => void
  onOpenSettings: () => void
  onOpenCommandPalette: () => void
}

/** List pages with a left-aligned title, a page icon, and the library's icon menus. Creating a page opens its title for editing. */
export function PageSidebarView({ commandRef, pages, folders = [], folderCommands, onNavigateHeading, openPageId, settingsOpen, commandShortcut = '⌘K', onSelectPage, onCreatePage, onRenamePage, onDeletePage, onOpenThemes, onOpenSettings, onOpenCommandPalette }: PageSidebarViewProps) {
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set())
  const [expandedPages, setExpandedPages] = useState<Set<string>>(new Set())
  const [selectedFolder, setSelectedFolder] = useState<string>()
  const [folderAction, setFolderAction] = useState<FolderAction>()
  const [treeError, setTreeError] = useState('')
  /** Find the current document's location independently of its body. */
  function currentPage(page: PageSummary) {
    return page.pageId === openPageId
  }
  const currentFolder = pages.find(currentPage)?.folderId
  /** Track the active location without resetting a newly selected creation folder. */
  function ancestorId(folder: NotebookFolder) {
    return folder.folderId
  }
  const ancestorKey = folderAncestors(folders, currentFolder).map(ancestorId).join('/')
  /** Reveal a page selected through search or moved into a collapsed folder. */
  function revealLocation() {
    const ancestors = folderAncestors(folders, currentFolder)
    /** Merge ancestor expansion without closing unrelated branches. */
    function expand(previous: Set<string>) {
      const next = new Set(previous)
      for (const folder of ancestors) next.add(folder.folderId)
      return next
    }
    setExpandedFolders(expand)
    setSelectedFolder(currentFolder)
  }
  useEffect(revealLocation, [openPageId, currentFolder, ancestorKey])
  /** Create a container beside the currently selected folder's children. */
  function newFolder() {
    setFolderAction({ kind: 'create', parentId: selectedFolder })
  }
  /** Return creation to the notebook's top level. */
  function selectRoots() {
    setSelectedFolder(undefined)
  }
  /** Dismiss an organizational form without changing documents. */
  function closeFolderDialog() {
    setFolderAction(undefined)
  }
  /** Reveal a newly created empty folder so its location is visible. */
  function folderCreated(id: string) {
    setSelectedFolder(id)
    setExpandedFolders(new Set([...expandedFolders, id]))
  }
  const titleRef = useRef<HTMLInputElement>(null)
  const pendingRenameRef = useRef(false)
  const [renamingPageId, setRenamingPageId] = useState<string | null>(null)
  const [mode, setMode] = useState<SidebarMode>('open')
  const [width, setWidth] = useState(defaultSidebarWidth)
  const [settingsMenuOpen, setSettingsMenuOpen] = useState(false)
  const [actionsPage, setActionsPage] = useState<string | null>(null)
  const [resizing, setResizing] = useState(false)
  const canDelete = pages.length > 1
  const slotStyle: CSSProperties | undefined = mode === 'open' ? { width } : undefined
  const slotClass = resizing ? 'page-sidebar-slot is-resizing' : 'page-sidebar-slot'

  /** Run sidebar and page menu commands using the same state as the buttons. */
  function sidebarCommand(id: string) {
    switch (id) {
      case 'workspace.sidebar.settings':
        showSidebar()
        setSettingsMenuOpen(true)
        break
      case 'workspace.page.actions':
        showSidebar()
        setActionsPage(openPageId)
        break
      case 'workspace.sidebar.hide':
        hideSidebar()
        break
      case 'workspace.sidebar.collapse':
        setMode('collapsed')
        break
      case 'workspace.sidebar.show':
      case 'workspace.sidebar.expand':
        showSidebar()
        break
      case 'workspace.page.create':
        handleCreatePage()
        break
      case 'workspace.page.rename':
        showSidebar()
        onSelectPage(openPageId)
        setRenamingPageId(openPageId)
        break
      case 'workspace.page.delete':
        if (!canDelete) return false
        onDeletePage(openPageId)
        break
      default:
        return false
    }
    return true
  }
  /** Register the sidebar dispatcher while the sidebar is mounted. */
  function bindCommands() {
    return sidebarCommand
  }
  useImperativeHandle(commandRef, bindCommands)

  /** Focus the document title when a new page is ready, so writing starts in the page itself. */
  function renameCreatedPage() {
    if (!pendingRenameRef.current) return
    pendingRenameRef.current = false
    const title = document.querySelector<HTMLInputElement>('.workspace-notes .page-title')
    title?.focus()
    title?.select()
  }
  useEffect(renameCreatedPage, [openPageId])

  /** Select the title text while a page is being renamed. */
  function focusRenameField() {
    if (renamingPageId === null) return
    titleRef.current?.focus()
    titleRef.current?.select()
  }
  useEffect(focusRenameField, [renamingPageId])

  /** Ask for an empty page, show the full list, and focus its document title once it is open. */
  function handleCreatePage() {
    setMode('open')
    pendingRenameRef.current = true
    onCreatePage(selectedFolder)
  }

  /** Switch between the full list and the icon column. */
  function toggleCollapsed() {
    setMode(mode === 'collapsed' ? 'open' : 'collapsed')
  }

  /** Animate the list shut. The show control brings the saved width back. */
  function hideSidebar() {
    setMode('hidden')
  }

  /** Animate the list open at its last dragged width. */
  function showSidebar() {
    setMode('open')
  }

  /** Drag the list's trailing edge. The width follows the pointer until the pointer is released. */
  function startResize(event: ReactPointerEvent<HTMLDivElement>) {
    if (mode !== 'open') return
    event.preventDefault()
    const handle = event.currentTarget
    const originX = event.clientX
    const originWidth = width
    handle.setPointerCapture(event.pointerId)
    setResizing(true)

    /** Apply the pointer's horizontal movement to the list width. */
    function moveResize(moveEvent: PointerEvent) {
      setWidth(clampSidebarWidth(originWidth + moveEvent.clientX - originX))
    }

    /** Stop following the pointer and let the width animate again. */
    function endResize() {
      handle.removeEventListener('pointermove', moveResize)
      handle.removeEventListener('pointerup', endResize)
      handle.removeEventListener('pointercancel', endResize)
      setResizing(false)
    }

    handle.addEventListener('pointermove', moveResize)
    handle.addEventListener('pointerup', endResize)
    handle.addEventListener('pointercancel', endResize)
  }

  /** Nudge the list width from the keyboard. Shift moves by a larger step. */
  function nudgeResize(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
    event.preventDefault()
    const step = event.shiftKey ? 24 : 8
    const direction = event.key === 'ArrowLeft' ? -1 : 1
    setWidth(clampSidebarWidth(width + direction * step))
  }

  /** Render one page row with its overflow menu and right-click menu. */
  function renderPage(page: PageSummary) {
    const isOpen = page.pageId === openPageId && !settingsOpen
    const isRenaming = page.pageId === renamingPageId
    const title = page.title

    /** Show this page. */
    function selectThisPage() {
      setSelectedFolder(page.folderId)
      onSelectPage(page.pageId)
    }

    /** Show the full list, select this page, and replace its title with an editable field. */
    function beginRename() {
      setMode('open')
      onSelectPage(page.pageId)
      setRenamingPageId(page.pageId)
    }

    /** Store the title as it is typed, including a blank field. */
    function handleTitleChange(event: ChangeEvent<HTMLInputElement>) {
      onRenamePage(page.pageId, event.target.value)
    }

    /** Leave the title field after Enter. */
    function handleTitleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
      if (event.key !== 'Enter') return
      event.preventDefault()
      setRenamingPageId(null)
    }

    /** Leave the title field when it loses focus. */
    function finishRename() {
      setRenamingPageId(null)
    }

    /** Remove this page. The last page cannot be removed. */
    function deleteThisPage() {
      if (!canDelete) return
      if (renamingPageId === page.pageId) setRenamingPageId(null)
      onDeletePage(page.pageId)
    }

    /** Keep a page menu opened by its button or the palette in sync. */
    function changeActions(open: boolean) {
      setActionsPage(open ? page.pageId : null)
    }
    /** Toggle this page's live outline without changing its selection. */
    function toggleOutline() {
      const next = new Set(expandedPages)
      if (next.has(page.pageId)) next.delete(page.pageId)
      else next.add(page.pageId)
      setExpandedPages(next)
    }
    /** Move this page through the shared folder picker. */
    function moveThisPage() {
      setFolderAction({ kind: 'move-page', pageId: page.pageId, title: page.title, folderId: page.folderId })
    }
    const rowClass = isOpen ? 'page-sidebar-row is-open' : 'page-sidebar-row'
    const pageTitle = title || 'Untitled'
    const selectButton = (
      <button type="button" className="page-sidebar-select" aria-current={isOpen ? 'page' : undefined} aria-label={pageTitle} onClick={selectThisPage}>
        <PageIcon />
        <span className="page-sidebar-label">{pageTitle}</span>
      </button>
    )

    return (
      <li key={page.pageId}>
        <ContextMenu.Root>
          <ContextMenu.Trigger className={rowClass}>
            {mode === 'open' && (
              <button className="page-tree-toggle" aria-label={`${expandedPages.has(page.pageId) ? 'Collapse' : 'Expand'} headings for ${pageTitle}`} aria-expanded={expandedPages.has(page.pageId)} onClick={toggleOutline}>
                <ChevronRight size={14} />
              </button>
            )}
            {isRenaming ? (
              <input ref={titleRef} className="page-sidebar-title" aria-label="Page title" value={title} onChange={handleTitleChange} onBlur={finishRename} onKeyDown={handleTitleKeyDown} />
            ) : mode === 'collapsed' ? (
              <IconTooltip label={pageTitle} side="right">
                {selectButton}
              </IconTooltip>
            ) : (
              selectButton
            )}
            <div className="page-sidebar-actions">
              <Menu.Root open={actionsPage === page.pageId} onOpenChange={changeActions}>
                <IconTooltip label="Page actions">
                  <Menu.Trigger className="primitive-icon-button primitive-icon-quiet" aria-label={`Actions for ${title || 'Untitled'}`}>
                    <MoreActionsIcon />
                  </Menu.Trigger>
                </IconTooltip>
                <Menu.Portal>
                  <Menu.Positioner sideOffset={6} align="start">
                    <Menu.Popup className="primitive-popup">
                      <Menu.Item className="primitive-item" onClick={beginRename}>
                        <span className="primitive-item-label">
                          <CellEditingIcon /> Rename
                        </span>
                      </Menu.Item>
                      <Menu.Item className="primitive-item" onClick={moveThisPage}>
                        Move to folder…
                      </Menu.Item>
                      <Menu.Separator className="primitive-separator" />
                      <Menu.Item className="primitive-item primitive-item-danger" disabled={!canDelete} onClick={deleteThisPage}>
                        <span className="primitive-item-label">
                          <DeleteIcon /> Delete
                        </span>
                      </Menu.Item>
                    </Menu.Popup>
                  </Menu.Positioner>
                </Menu.Portal>
              </Menu.Root>
            </div>
          </ContextMenu.Trigger>
          <ContextMenu.Portal>
            <ContextMenu.Positioner>
              <ContextMenu.Popup className="primitive-popup">
                <ContextMenu.Item className="primitive-item" onClick={beginRename}>
                  <span className="primitive-item-label">
                    <CellEditingIcon /> Rename
                  </span>
                </ContextMenu.Item>
                <ContextMenu.Item className="primitive-item" onClick={moveThisPage}>
                  Move to folder…
                </ContextMenu.Item>
                <ContextMenu.Separator className="primitive-separator" />
                <ContextMenu.Item className="primitive-item primitive-item-danger" disabled={!canDelete} onClick={deleteThisPage}>
                  <span className="primitive-item-label">
                    <DeleteIcon /> Delete
                  </span>
                </ContextMenu.Item>
              </ContextMenu.Popup>
            </ContextMenu.Positioner>
          </ContextMenu.Portal>
        </ContextMenu.Root>
        {mode === 'open' && expandedPages.has(page.pageId) && onNavigateHeading && <NotebookOutlineView pageId={page.pageId} onNavigate={onNavigateHeading} />}
      </li>
    )
  }

  /** Render one folder with the same menu and disclosure conventions as page rows. */
  function renderFolder(folder: NotebookFolder) {
    const expanded = expandedFolders.has(folder.folderId)
    /** Select this creation location and toggle its children. */
    function toggle() {
      setSelectedFolder(folder.folderId)
      const next = new Set(expandedFolders)
      if (expanded) next.delete(folder.folderId)
      else next.add(folder.folderId)
      setExpandedFolders(next)
    }
    /** Create a page inside this folder even when a different page is open. */
    function addPage() {
      setMode('open')
      pendingRenameRef.current = true
      setExpandedFolders(new Set([...expandedFolders, folder.folderId]))
      onCreatePage(folder.folderId)
    }
    /** Create a nested organizational container. */
    function addFolder() {
      setExpandedFolders(new Set([...expandedFolders, folder.folderId]))
      setFolderAction({ kind: 'create', parentId: folder.folderId })
    }
    /** Rename only this folder. */
    function renameFolder() {
      setFolderAction({ kind: 'rename', folder })
    }
    /** Open the validated destination picker. */
    function moveFolder() {
      setFolderAction({ kind: 'move-folder', folder })
    }
    /** Remove a container while keeping its pages and subfolders in the parent. */
    function removeFolder() {
      try {
        folderCommands?.deleteFolder(folder.folderId)
        setSelectedFolder(folder.parentId)
        setTreeError('')
      } catch (failure) {
        setTreeError(failure instanceof Error ? failure.message : String(failure))
      }
    }
    return (
      <li key={folder.folderId}>
        <div className={`page-sidebar-row page-folder-row${selectedFolder === folder.folderId ? ' is-location' : ''}`}>
          <button className="page-sidebar-select" aria-label={`Folder ${folder.title}`} aria-expanded={expanded} onClick={toggle}>
            <ChevronRight className="folder-chevron" size={14} />
            {expanded ? <FolderOpen size={16} /> : <Folder size={16} />}
            <span className="page-sidebar-label">{folder.title}</span>
          </button>
          <div className="page-sidebar-actions">
            <Menu.Root>
              <Menu.Trigger className="primitive-icon-button primitive-icon-quiet" aria-label={`Actions for folder ${folder.title}`}>
                <MoreActionsIcon />
              </Menu.Trigger>
              <Menu.Portal>
                <Menu.Positioner sideOffset={6} align="start">
                  <Menu.Popup className="primitive-popup">
                    <Menu.Item className="primitive-item" onClick={addPage}>
                      New page inside
                    </Menu.Item>
                    <Menu.Item className="primitive-item" onClick={addFolder}>
                      New folder inside
                    </Menu.Item>
                    <Menu.Item className="primitive-item" onClick={renameFolder}>
                      Rename
                    </Menu.Item>
                    <Menu.Item className="primitive-item" onClick={moveFolder}>
                      Move to folder…
                    </Menu.Item>
                    <Menu.Separator className="primitive-separator" />
                    <Menu.Item className="primitive-item" onClick={removeFolder}>
                      Remove folder, keep contents
                    </Menu.Item>
                  </Menu.Popup>
                </Menu.Positioner>
              </Menu.Portal>
            </Menu.Root>
          </div>
        </div>
        {expanded && <ul className="page-tree-children">{renderChildren(folder.folderId)}</ul>}
      </li>
    )
  }
  /** List each folder's immediate children; page ordering is preserved within each location. */
  function renderChildren(parentId?: string) {
    /** Select direct child containers. */
    function childFolder(folder: NotebookFolder) {
      return folder.parentId === parentId
    }
    /** Select documents in this location. */
    function childPage(page: PageSummary) {
      return page.folderId === parentId
    }
    const childFolders = folders.filter(childFolder)
    const childPages = pages.filter(childPage)
    return (
      <>
        {childFolders.map(renderFolder)}
        {childPages.map(renderPage)}
        {parentId && !childFolders.length && !childPages.length && <li className="page-outline-empty">Empty folder</li>}
      </>
    )
  }

  const collapseLabel = mode === 'collapsed' ? 'Expand pages' : 'Collapse pages'
  const railTooltipSide = mode === 'collapsed' ? 'right' : 'top'
  const settingsClass = settingsOpen ? 'page-sidebar-settings is-open' : 'page-sidebar-settings'
  const settingsTrigger = (
    <Menu.Trigger className={settingsClass} aria-label="Settings">
      <GearIcon />
      <span className="page-sidebar-label">Settings</span>
    </Menu.Trigger>
  )

  return (
    <Tooltip.Provider delay={220} closeDelay={0}>
      <div className={slotClass} data-mode={mode} style={slotStyle}>
        <aside className="page-sidebar" aria-label="Pages" inert={mode === 'hidden' ? true : undefined}>
          <div className="page-sidebar-toolbar">
            <p className="page-sidebar-brand page-sidebar-label">Folio</p>
            <div className="page-sidebar-toolbar-actions">
              <IconTooltip label={collapseLabel} side={railTooltipSide}>
                <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label={collapseLabel} aria-expanded={mode === 'open'} onClick={toggleCollapsed}>
                  {mode === 'collapsed' ? <SidebarExpandIcon /> : <SidebarCollapseIcon />}
                </button>
              </IconTooltip>
            </div>
          </div>
          <div className="page-sidebar-shortcuts">
            <button type="button" className="page-sidebar-shortcut" onClick={onOpenCommandPalette} aria-label="Search pages and commands">
              <SearchIcon />
              <span className="page-sidebar-label">Search</span>
              <kbd className="page-sidebar-label">{commandShortcut}</kbd>
            </button>
            <button type="button" className="page-sidebar-shortcut" onClick={handleCreatePage} aria-label="New page">
              <PlusIcon />
              <span className="page-sidebar-label">New page</span>
            </button>
          </div>
          <div className="page-tree-heading">
            <button className="page-sidebar-heading" onClick={selectRoots} aria-label="Roots, top level">
              Roots
            </button>
            <button className="primitive-icon-button primitive-icon-quiet" onClick={newFolder} aria-label="New folder" title="New folder">
              <FolderPlus size={16} />
            </button>
          </div>
          {treeError && <p role="alert">{treeError}</p>}
          <ul className="page-sidebar-list">{mode === 'collapsed' ? pages.map(renderPage) : renderChildren()}</ul>
          <div className="page-sidebar-footer">
            <Menu.Root open={settingsMenuOpen} onOpenChange={setSettingsMenuOpen}>
              {mode === 'collapsed' ? (
                <IconTooltip label="Settings" side="right">
                  {settingsTrigger}
                </IconTooltip>
              ) : (
                settingsTrigger
              )}
              <Menu.Portal>
                <Menu.Positioner side={mode === 'collapsed' ? 'right' : 'top'} sideOffset={6} align="start">
                  <Menu.Popup className="primitive-popup">
                    {onOpenThemes && (
                      <Menu.Item className="primitive-item" onClick={onOpenThemes}>
                        <span className="primitive-item-label">
                          <GearIcon /> Themes
                        </span>
                      </Menu.Item>
                    )}
                    <Menu.Item className="primitive-item" onClick={onOpenSettings}>
                      <span className="primitive-item-label">
                        <KeyboardIcon /> Settings
                      </span>
                    </Menu.Item>
                    <Menu.Item className="primitive-item" onClick={onOpenCommandPalette}>
                      <span className="primitive-item-label">
                        <SearchIcon /> Command palette
                      </span>
                    </Menu.Item>
                  </Menu.Popup>
                </Menu.Positioner>
              </Menu.Portal>
            </Menu.Root>
          </div>
        </aside>
        {mode === 'open' ? (
          <div className="page-sidebar-resize" role="separator" tabIndex={0} aria-label="Resize pages" aria-orientation="vertical" aria-valuemin={minSidebarWidth} aria-valuemax={maxSidebarWidth} aria-valuenow={Math.round(width)} onPointerDown={startResize} onKeyDown={nudgeResize} />
        ) : null}
      </div>
      {folderAction && folderCommands && <NotebookFolderDialog action={folderAction} folders={folders} commands={folderCommands} onClose={closeFolderDialog} onCreated={folderCreated} />}
      {mode === 'hidden' ? (
        <div className="page-sidebar-reveal">
          <IconTooltip label="Show pages">
            <button type="button" className="primitive-icon-button" aria-label="Show pages" onClick={showSidebar}>
              <SidebarShowIcon />
            </button>
          </IconTooltip>
        </div>
      ) : null}
    </Tooltip.Provider>
  )
}
