/**
 * Render the notebook page list. Contains the icon that creates a page, each page's title, the overflow menu and right-click menu, the controls that resize, collapse, or hide the list, and the settings menu at the bottom. This view does not store the pages or the shortcut labels.
 *
 * @file
 */

import { useEffect, useImperativeHandle, useRef, useState } from 'react'
import type { ChangeEvent, CSSProperties, KeyboardEvent, PointerEvent as ReactPointerEvent } from 'react'
import { ContextMenu } from '@base-ui/react/context-menu'
import { Menu } from '@base-ui/react/menu'
import { Tooltip } from '@base-ui/react/tooltip'
import { CellEditingIcon, DeleteIcon, GearIcon, KeyboardIcon, MoreActionsIcon, PageIcon, PlusIcon, SearchIcon, SidebarCollapseIcon, SidebarExpandIcon, SidebarHideIcon, SidebarShowIcon } from '#/component-library/icons/folio-icons.tsx'
import { IconTooltip } from '#/component-library/primitives/icon-tooltip.tsx'
import type { Page } from '#/notebook/page.ts'

/** The page list is open, reduced to icons, or fully hidden. */
type SidebarMode = 'open' | 'collapsed' | 'hidden'

const defaultSidebarWidth = 280
const minSidebarWidth = 220
const maxSidebarWidth = 440

/** Keep a dragged page-list width between the narrowest useful column and the widest column that still leaves the page readable. */
function clampSidebarWidth(width: number) {
  return Math.min(maxSidebarWidth, Math.max(minSidebarWidth, width))
}

/** Receive the pages to list, whether keyboard shortcuts are on screen, and the callbacks that select, create, rename, or delete a page or open a settings destination. */
interface PageSidebarViewProps {
  commandRef?: React.Ref<(id: string) => boolean>
  pages: readonly Pick<Page, 'pageId' | 'title'>[]
  openPageId: string
  settingsOpen: boolean
  onSelectPage: (pageId: string) => void
  onCreatePage: () => void
  onRenamePage: (pageId: string, title: string) => void
  onDeletePage: (pageId: string) => void
  onOpenThemes?: () => void
  onOpenSettings: () => void
  onOpenCommandPalette: () => void
}

/** List pages with a left-aligned title, a page icon, and the library's icon menus. Creating a page opens its title for editing. */
export function PageSidebarView({ commandRef, pages, openPageId, settingsOpen, onSelectPage, onCreatePage, onRenamePage, onDeletePage, onOpenThemes, onOpenSettings, onOpenCommandPalette }: PageSidebarViewProps) {
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

  /** Open the title field for a page that was just created. */
  function renameCreatedPage() {
    if (!pendingRenameRef.current) return
    pendingRenameRef.current = false
    setRenamingPageId(openPageId)
  }
  useEffect(renameCreatedPage, [openPageId])

  /** Select the title text while a page is being renamed. */
  function focusRenameField() {
    if (renamingPageId === null) return
    titleRef.current?.focus()
    titleRef.current?.select()
  }
  useEffect(focusRenameField, [renamingPageId])

  /** Ask for an empty page, show the full list, and edit its title once it is open. */
  function handleCreatePage() {
    setMode('open')
    pendingRenameRef.current = true
    onCreatePage()
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
  function renderPage(page: Pick<Page, 'pageId' | 'title'>) {
    const isOpen = page.pageId === openPageId && !settingsOpen
    const isRenaming = page.pageId === renamingPageId
    const title = page.title

    /** Show this page. */
    function selectThisPage() {
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
      </li>
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
            <p className="page-sidebar-heading">Pages</p>
            <div className="page-sidebar-toolbar-actions">
              <IconTooltip label={collapseLabel} side={railTooltipSide}>
                <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label={collapseLabel} aria-expanded={mode === 'open'} onClick={toggleCollapsed}>
                  {mode === 'collapsed' ? <SidebarExpandIcon /> : <SidebarCollapseIcon />}
                </button>
              </IconTooltip>
              <IconTooltip label="Hide pages" side={railTooltipSide}>
                <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label="Hide pages" onClick={hideSidebar}>
                  <SidebarHideIcon />
                </button>
              </IconTooltip>
              <IconTooltip label="New page" side={railTooltipSide}>
                <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label="New page" onClick={handleCreatePage}>
                  <PlusIcon />
                </button>
              </IconTooltip>
            </div>
          </div>
          <ul className="page-sidebar-list">{pages.map(renderPage)}</ul>
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
                        <KeyboardIcon /> Keyboard shortcuts
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
