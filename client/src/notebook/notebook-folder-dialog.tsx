/**
 * Create, rename, or relocate sidebar items through one focused dialog. Destination choices display full paths and exclude cycles; persistence failures keep the form open.
 *
 * @file
 */
import { useState } from 'react'
import type { ChangeEvent, FormEvent } from 'react'
import { Dialog } from '@base-ui/react/dialog'
import { Button } from '../component-library'
import type { NotebookFolder } from '../state/global-states'
import { folderAncestors, folderPath } from './notebook-folders'

export type FolderAction = { kind: 'create'; parentId?: string } | { kind: 'rename'; folder: NotebookFolder } | { kind: 'move-folder'; folder: NotebookFolder } | { kind: 'move-page'; pageId: string; title: string; folderId?: string }
export interface FolderActions {
  createFolder: (title: string, parentId?: string) => string
  renameFolder: (id: string, title: string) => void
  relocateFolder: (id: string, parentId?: string) => void
  relocatePage: (id: string, folderId?: string) => void
  deleteFolder: (id: string) => void
}

/** Edit one organizational operation without mutating state until submission succeeds. */
export function NotebookFolderDialog({ action, folders, commands, onClose, onCreated }: { action: FolderAction; folders: readonly NotebookFolder[]; commands: FolderActions; onClose: () => void; onCreated: (id: string) => void }) {
  const moving = action.kind === 'move-folder' || action.kind === 'move-page'
  const [name, setName] = useState(action.kind === 'rename' ? action.folder.title : '')
  const [parent, setParent] = useState(action.kind === 'create' ? (action.parentId ?? '') : action.kind === 'move-page' ? (action.folderId ?? '') : (action.folder.parentId ?? ''))
  const [error, setError] = useState('')
  const title = action.kind === 'create' ? 'New folder' : action.kind === 'rename' ? 'Rename folder' : `Move ${action.kind === 'move-page' ? action.title || 'Untitled' : action.folder.title}`
  /** Keep typed names local until the user confirms. */
  function changeName(event: ChangeEvent<HTMLInputElement>) {
    setName(event.target.value)
  }
  /** Choose a destination by identity rather than title. */
  function changeParent(event: ChangeEvent<HTMLSelectElement>) {
    setParent(event.target.value)
  }
  /** Close from Escape or the dialog dismissal control. */
  function openChanged(open: boolean) {
    if (!open) onClose()
  }
  /** Persist the requested change and dismiss only after a successful write. */
  function submit(event: FormEvent) {
    event.preventDefault()
    try {
      if (action.kind === 'create') onCreated(commands.createFolder(name, parent || undefined))
      else if (action.kind === 'rename') commands.renameFolder(action.folder.folderId, name)
      else if (action.kind === 'move-folder') commands.relocateFolder(action.folder.folderId, parent || undefined)
      else commands.relocatePage(action.pageId, parent || undefined)
      onClose()
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure))
    }
  }
  /** Exclude a moved folder and its descendants from its own destination choices. */
  function destination(folder: NotebookFolder) {
    /** Detect a parent chain containing the moved folder. */
    function isMoved(ancestor: NotebookFolder) {
      return action.kind === 'move-folder' && ancestor.folderId === action.folder.folderId
    }
    const disabled = action.kind === 'move-folder' && folderAncestors(folders, folder.folderId).some(isMoved)
    return (
      <option key={folder.folderId} value={folder.folderId} disabled={disabled}>
        {folderPath(folders, folder.folderId)}
      </option>
    )
  }
  return (
    <Dialog.Root open onOpenChange={openChanged}>
      <Dialog.Portal>
        <Dialog.Backdrop className="focus-cell-backdrop" />
        <Dialog.Popup className="focus-cell-dialog folder-dialog">
          <Dialog.Title className="focus-cell-title">{title}</Dialog.Title>
          <form onSubmit={submit}>
            {!moving && (
              <label>
                Folder name
                <input aria-label="Folder name" value={name} onChange={changeName} required maxLength={120} autoFocus />
              </label>
            )}
            {action.kind !== 'rename' && (
              <label>
                {moving ? 'Move to' : 'Inside'}
                <select aria-label="Destination folder" value={parent} onChange={changeParent}>
                  <option value="">Roots</option>
                  {folders.map(destination)}
                </select>
              </label>
            )}
            {error && <p role="alert">{error}</p>}
            <div className="folder-dialog-actions">
              <Button type="submit">{moving ? 'Move' : action.kind === 'create' ? 'Create folder' : 'Save name'}</Button>
              <Button variant="quiet" onClick={onClose}>
                Cancel
              </Button>
            </div>
          </form>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
