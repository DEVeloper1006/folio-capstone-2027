/**
 * Organize the sidebar through folder identities and parent links. Page bodies stay in their existing records; moving or removing a folder changes one sidebar record and never deletes document content.
 *
 * @file
 */
import type { NotebookState, NotebookFolder } from '../state/global-states'

/** Find a folder and its ancestors, nearest first, rejecting broken links and cycles. */
export function folderAncestors(folders: readonly NotebookFolder[], folderId?: string): NotebookFolder[] {
  const result: NotebookFolder[] = []
  const seen = new Set<string>()
  while (folderId) {
    if (seen.has(folderId)) throw new Error('This folder tree contains a cycle. Nothing was moved.')
    seen.add(folderId)
    const id = folderId
    /** Resolve the next parent by stable identity. */
    function matches(folder: NotebookFolder) {
      return folder.folderId === id
    }
    const folder = folders.find(matches)
    if (!folder) throw new Error('This folder no longer exists. Choose another destination.')
    result.push(folder)
    folderId = folder.parentId
  }
  return result
}
/** Display the full location when folder names alone are ambiguous. */
export function folderPath(folders: readonly NotebookFolder[], id?: string) {
  /** Read a folder's human-readable name. */
  function title(folder: NotebookFolder) {
    return folder.title
  }
  return ['Roots', ...folderAncestors(folders, id).reverse().map(title)].join(' / ')
}
/** Require a meaningful folder name without treating names as filesystem paths. */
export function folderTitle(title: string) {
  const value = title.trim()
  if (!value || value.length > 120) throw new Error('Use a folder name between 1 and 120 characters.')
  return value
}
/** Move a page by changing only its sidebar location. */
export function movePageToFolder(list: NotebookState, pageId: string, folderId?: string): NotebookState {
  folderAncestors(list.folders ?? [], folderId)
  /** Preserve title and identity while replacing the location. */
  function move(page: NotebookState['pages'][number]) {
    return page.pageId === pageId ? { ...page, folderId } : page
  }
  return { ...list, pages: list.pages.map(move) }
}
/** Move a folder with all its contents, refusing self-parenting and descendant destinations. */
export function moveFolder(list: NotebookState, folderId: string, parentId?: string): NotebookState {
  const folders = list.folders ?? []
  folderAncestors(folders, folderId)
  /** Refuse a parent chain that would lead back to the moved folder. */
  function contains(folder: NotebookFolder) {
    return folder.folderId === folderId
  }
  if (folderAncestors(folders, parentId).some(contains)) throw new Error('A folder cannot be moved inside itself or its own subfolders.')
  /** Retain every descendant's existing parent link. */
  function move(folder: NotebookFolder) {
    return folder.folderId === folderId ? { ...folder, parentId } : folder
  }
  return { ...list, folders: folders.map(move) }
}
/** Remove only the folder container; promote its pages and subfolders to its parent. */
export function removeFolder(list: NotebookState, folderId: string): NotebookState {
  const removed = folderAncestors(list.folders ?? [], folderId).at(0)
  if (!removed) return list
  const parentId = removed.parentId
  const folders: NotebookFolder[] = []
  for (const folder of list.folders ?? []) {
    if (folder.folderId !== folderId) folders.push(folder.parentId === folderId ? { ...folder, parentId } : folder)
  }
  /** Keep every document and update only direct children's locations. */
  function promote(page: NotebookState['pages'][number]) {
    return page.folderId === folderId ? { ...page, folderId: parentId } : page
  }
  return { ...list, folders, pages: list.pages.map(promote) }
}
