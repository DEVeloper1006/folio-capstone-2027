/**
 * Store page subscriptions in React Query. Desktop writes are acknowledged by the journaled Markdown Roots store before publication; browser previews use session storage. Preserve the original local-storage notebook during migration.
 *
 * @file
 */

import type { NotebookSnapshot } from './notebook-storage'
import { folderAncestors, folderTitle, moveFolder, movePageToFolder, removeFolder } from './notebook-folders'
import { useLayoutEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { QueryClient } from '@tanstack/react-query'
import { createCellId } from './notebook-cells.ts'
import { createEmptyPage, nextUntitledTitle, defaultPageMetadata } from './page.ts'
import { createSamplePage, createPracticePages } from './sample-page.ts'
import type { NotebookCell } from './notebook-cells.ts'
import type { Page } from './page.ts'

import type { NotebookState as PageList, PageSummary } from '#/state/global-states.ts'

/** Persist desktop notebooks across application restarts while preserving browser tab isolation. */
function notebookStorage() {
  return window.folioDesktop ? localStorage : sessionStorage
}

const desktopPages = new Map<string, Page>()
const rootsKey = ['notebook', 'roots'] as const
const listKey = ['notebook', 'pages'] as const
const storagePrefix = 'folio:notebook:v1:'
const sample = createSamplePage()
const practicePages = createPracticePages()
const initialPages = [sample, ...practicePages]

/** Identify a page independently of the sidebar list. */
function pageKey(id: string) {
  return ['notebook', 'page', id] as const
}

/** Keep cell edits out of the sidebar subscription. */
function summary({ pageId, title }: Page): PageSummary {
  return { pageId, title }
}

/** Seed each router's cache independently, including during server rendering. */
export function seedNotebook(client: QueryClient) {
  for (const page of initialPages) client.setQueryData(pageKey(page.pageId), page)
  client.setQueryData<PageList>(listKey, { pages: initialPages.map(summary), openPageId: sample.pageId })
}

/** Save a page before publishing its new value to editors. */
function writePage(client: QueryClient, page: Page) {
  try {
    if (window.folioDesktop) {
      window.folioDesktop.saveNotebookPage(page)
      desktopPages.set(page.pageId, page)
    } else notebookStorage().setItem(storagePrefix + page.pageId, JSON.stringify(page))
    client.setQueryData(pageKey(page.pageId), page)
  } catch (error) {
    storageFailure(client, error)
    throw error
  }
}
/** Save sidebar order and the selected page together. */
function writeList(client: QueryClient, list: PageList) {
  try {
    if (window.folioDesktop) window.folioDesktop.saveNotebookList(list)
    else notebookStorage().setItem(storagePrefix + 'list', JSON.stringify(list))
    client.setQueryData(listKey, list)
  } catch (error) {
    storageFailure(client, error)
    throw error
  }
}
/** Surface failed disk writes without claiming that the changed document was saved. */
function storageFailure(client: QueryClient, error: unknown) {
  const previous = client.getQueryData<{ path: string; error: string }>(rootsKey)
  client.setQueryData(rootsKey, { path: previous?.path ?? '', error: error instanceof Error ? error.message : String(error) })
}

/** Read sidebar order and selection saved by this tab. */
function loadPageList(): PageList {
  const stored = notebookStorage().getItem(storagePrefix + 'list')
  const list: PageList = stored ? JSON.parse(stored) : { pages: initialPages.map(summary), openPageId: sample.pageId }
  const addedKey = storagePrefix + 'practice-pages-added'
  if (notebookStorage().getItem(addedKey)) return list
  /** Add starter pages once without restoring any that the user subsequently deletes. */
  function missing(page: Page) {
    /** Match a starter page by its stable id. */
    function matches(entry: PageSummary) {
      return entry.pageId === page.pageId
    }
    return !list.pages.some(matches)
  }
  const next = { ...list, pages: [...list.pages, ...practicePages.filter(missing).map(summary)] }
  notebookStorage().setItem(storagePrefix + 'list', JSON.stringify(next))
  notebookStorage().setItem(addedKey, 'true')
  return next
}

/** Read the stored page, using the bundled example until it is first edited. */
function loadPage(pageId: string): Page {
  const desktop = desktopPages.get(pageId)
  if (desktop) return desktop
  const record = notebookStorage().getItem(storagePrefix + pageId)
  if (record) {
    const page = JSON.parse(record) as Page
    return { ...page, pageMetadata: { ...defaultPageMetadata, ...page.pageMetadata } }
  }
  /** Resolve a bundled page that has not yet been edited. */
  function matches(page: Page) {
    return page.pageId === pageId
  }
  const initial = initialPages.find(matches)
  if (initial) return initial
  throw new Error('The saved notebook page is missing')
}

/** Subscribe to page titles and selection. Restore saved pages before the hydrated notebook accepts input. */
export function usePageList() {
  const client = useQueryClient()
  /** Load this tab's saved records as one notebook. The initial sample can have no saved record yet. */
  function restoreNotebook() {
    try {
      const list = loadPageList()
      if (window.folioDesktop) {
        /** Read every legacy page before the first filesystem migration. */
        function legacyPage(entry: PageSummary) {
          return loadPage(entry.pageId)
        }
        const loaded = window.folioDesktop.loadNotebook(JSON.stringify({ version: 1, list, pages: list.pages.map(legacyPage) }))
        publishRoots(client, loaded)
      } else {
        for (const page of initialPages) client.setQueryData(pageKey(page.pageId), loadPage(page.pageId))
        if (list.openPageId !== sample.pageId) client.setQueryData(pageKey(list.openPageId), loadPage(list.openPageId))
        client.setQueryData(listKey, list)
      }
    } catch (error) {
      client.setQueryData(rootsKey, { path: '', error: error instanceof Error ? error.message : String(error) })
    }
  }
  useLayoutEffect(restoreNotebook, [client])
  const { data: list } = useQuery<PageList>({ queryKey: listKey, queryFn: loadPageList })
  if (!list) throw new Error('The notebook page list has not been initialized')
  const { data: roots } = useQuery({ queryKey: rootsKey, initialData: { path: '', error: '' }, enabled: false })
  return { ...list, roots }
}

/** Read the latest list directly when running a command between renders. */
function readList(client: QueryClient) {
  const list = client.getQueryData<PageList>(listKey)
  if (!list) throw new Error('The notebook page list has not been initialized')
  return list
}

/** Publish an already persisted root and replace all page subscriptions together. */
function publishRoots(client: QueryClient, loaded: { notebook: NotebookSnapshot; path: string }) {
  desktopPages.clear()
  for (const page of loaded.notebook.pages) {
    desktopPages.set(page.pageId, page)
    client.setQueryData(pageKey(page.pageId), page)
  }
  client.setQueryData(listKey, loaded.notebook.list)
  client.setQueryData(rootsKey, { path: loaded.path, error: '' })
}
/** Return commands bound to one query client. Page edits always target an explicit page id. */
export function notebookCommands(client: QueryClient) {
  /** Open an existing page. */
  function selectPage(id: string) {
    const list = readList(client)
    /** Only open a page that is still listed. */
    function matches(page: PageSummary) {
      return page.pageId === id
    }
    if (!list.pages.some(matches)) return
    if (!client.getQueryData(pageKey(id))) client.setQueryData(pageKey(id), loadPage(id))
    writeList(client, { ...list, openPageId: id })
  }
  /** Create and select an empty page. */
  function createPage(folderId?: string) {
    const list = readList(client)
    folderAncestors(list.folders ?? [], folderId)
    const page = createEmptyPage(nextUntitledTitle(list.pages))
    writePage(client, page)
    writeList(client, { ...list, pages: [...list.pages, { ...summary(page), folderId }], openPageId: page.pageId })
  }
  /** Apply a change to the latest version of the requested page. */
  function updatePage(id: string, change: (page: Page) => Page) {
    const page = client.getQueryData<Page>(pageKey(id))
    if (page) writePage(client, change(page))
  }
  /** Update the title in the document and sidebar. */
  function renamePage(id: string, title: string) {
    const list = readList(client)
    /** Replace the document title. */
    function rename(page: Page) {
      return { ...page, title }
    }
    /** Replace the matching sidebar title. */
    function renameSummary(page: PageSummary) {
      return page.pageId === id ? { ...page, title } : page
    }
    if (!client.getQueryData(pageKey(id))) client.setQueryData(pageKey(id), loadPage(id))
    updatePage(id, rename)
    writeList(client, { ...list, pages: list.pages.map(renameSummary) })
  }
  /** Remove a page and select a neighbor if the open page was removed. */
  function deletePage(id: string) {
    const list = readList(client)
    /** Match the requested page. */
    function matches(page: PageSummary) {
      return page.pageId === id
    }
    const index = list.pages.findIndex(matches)
    if (index < 0 || list.pages.length === 1) return
    const pages = [...list.pages]
    pages.splice(index, 1)
    writeList(client, { ...list, pages, openPageId: list.openPageId === id ? pages[Math.min(index, pages.length - 1)].pageId : list.openPageId })
    client.removeQueries({ queryKey: pageKey(id), exact: true })
    if (!window.folioDesktop) notebookStorage().removeItem(storagePrefix + id)
    desktopPages.delete(id)
  }
  /** Read the latest source for clipboard commands without subscribing to future edits. */
  function getPage(id: string) {
    return client.getQueryData<Page>(pageKey(id))
  }
  /** Create a folder in the selected location with no page-body writes. */
  function createFolder(title: string, parentId?: string) {
    const list = readList(client)
    folderAncestors(list.folders ?? [], parentId)
    const folderId = createCellId()
    writeList(client, { ...list, folders: [...(list.folders ?? []), { folderId, title: folderTitle(title), parentId }] })
    return folderId
  }
  /** Rename a container without changing any document names. */
  function renameFolder(folderId: string, title: string) {
    const list = readList(client)
    const name = folderTitle(title)
    folderAncestors(list.folders ?? [], folderId)
    /** Replace only the requested folder's title. */
    function rename(folder: NonNullable<PageList['folders']>[number]) {
      return folder.folderId === folderId ? { ...folder, title: name } : folder
    }
    writeList(client, { ...list, folders: list.folders?.map(rename) })
  }
  /** Persist all folder moves atomically in the existing sidebar record. */
  function relocateFolder(folderId: string, parentId?: string) {
    writeList(client, moveFolder(readList(client), folderId, parentId))
  }
  /** Persist a page's new folder without rewriting its body. */
  function relocatePage(pageId: string, folderId?: string) {
    writeList(client, movePageToFolder(readList(client), pageId, folderId))
  }
  /** Remove an organizational container while retaining all of its contents. */
  function deleteFolder(folderId: string) {
    writeList(client, removeFolder(readList(client), folderId))
  }
  /** Reload externally edited files without replacing the original legacy notebook. */
  function reloadRoots() {
    if (window.folioDesktop) publishRoots(client, window.folioDesktop.reloadNotebook())
  }
  return { reloadRoots, selectPage, createPage, renamePage, deletePage, updatePage, getPage, createFolder, renameFolder, relocateFolder, relocatePage, deleteFolder }
}

/** Subscribe to a slice of a page. Query keeps unchanged selections stable across edits. */
export function usePageSelection<T>(id: string, select: (page: Page) => T) {
  /** Load this page when its cache entry is missing. */
  function readPage() {
    return loadPage(id)
  }
  return useQuery<Page, Error, T>({ queryKey: pageKey(id), queryFn: readPage, select }).data
}

/** Append an empty cell of the requested kind. */
export function appendCell(page: Page, kind: 'math' | 'markdown', cellId = createCellId()): Page {
  const cell: NotebookCell = kind === 'math' ? { cellId, kind, latex: '' } : { cellId, kind, markdown: '' }
  return { ...page, cells: [...page.cells, cell] }
}

/** Replace one cell's source and preserve all other cells. */
export function editCell(page: Page, cellId: string, source: string): Page {
  /** Set the source field appropriate to the matching cell. */
  function replace(cell: NotebookCell): NotebookCell {
    if (cell.cellId !== cellId || cell.kind === 'graph') return cell
    return cell.kind === 'math' ? { ...cell, latex: source } : { ...cell, markdown: source }
  }
  return { ...page, cells: page.cells.map(replace) }
}
