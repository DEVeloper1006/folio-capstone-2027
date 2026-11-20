/**
 * Manage the local Markdown folder and complete editable backups through native pickers. Restores create a new root and never replace the current notebook.
 *
 * @file
 */
import { useState } from 'react'
import { Dialog } from '@base-ui/react/dialog'
import { Button } from '../component-library'

/** Expose filesystem organization and recovery without requiring users to locate hidden app storage. */
export function NotebookRoots({ path, onReload, onClose }: { path: string; onReload: () => void; onClose: () => void }) {
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  /** Keep a native picker's owner mounted until the operation settles. */
  function close(open: boolean) {
    if (!open && !busy) onClose()
  }
  /** Run one native operation and surface its actual result. */
  async function run(action: 'open' | 'reveal' | 'reload' | 'backup' | 'restore') {
    setBusy(true)
    setMessage('')
    try {
      const desktop = window.folioDesktop
      if (!desktop) throw new Error('Local Roots folders are available in Folio desktop.')
      if (action === 'reveal') await desktop.revealRoots()
      else if (action === 'backup') {
        const result = await desktop.backupRoots()
        setMessage(result.canceled ? 'Backup canceled.' : `Saved to ${result.path}`)
      } else if (action === 'reload') {
        onReload()
        setMessage('Roots reloaded from disk.')
      } else if (await (action === 'open' ? desktop.chooseRoots() : desktop.restoreRoots())) {
        onReload()
        setMessage(action === 'open' ? 'Opened the selected folder.' : 'Restored into a new folder. Your previous Roots is unchanged.')
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setBusy(false)
    }
  }
  /** Choose another local Markdown folder. */
  function openRoot() {
    void run('open')
  }
  /** Reveal ordinary Markdown files in the file manager. */
  function reveal() {
    void run('reveal')
  }
  /** Incorporate external edits immediately. */
  function reload() {
    void run('reload')
  }
  /** Save every page and its editable graph data. */
  function backup() {
    void run('backup')
  }
  /** Restore a portable notebook into a separate folder. */
  function restore() {
    void run('restore')
  }
  return (
    <Dialog.Root open onOpenChange={close}>
      <Dialog.Portal>
        <Dialog.Backdrop className="focus-cell-backdrop" />
        <Dialog.Popup className="focus-cell-dialog folder-dialog">
          <Dialog.Title className="focus-cell-title">Roots</Dialog.Title>
          <Dialog.Description>Notes are Markdown files in a local folder. Folio keeps block structure and editable graph views in its hidden .folio folder. Keep that folder with your notes.</Dialog.Description>
          <p className="roots-path">{path || 'No folder loaded'}</p>
          <div className="folder-dialog-actions">
            <Button onClick={reveal} disabled={busy}>
              Show folder
            </Button>
            <Button onClick={openRoot} disabled={busy}>
              Open folder…
            </Button>
            <Button onClick={reload} disabled={busy}>
              Reload
            </Button>
          </div>
          <div className="folder-dialog-actions">
            <Button onClick={backup} disabled={busy}>
              Save backup…
            </Button>
            <Button onClick={restore} disabled={busy}>
              Restore backup…
            </Button>
          </div>
          <p>Restoring creates a new folder. Existing notes are kept. App-wide settings stay in your settings file.</p>
          <p role="status">{busy ? 'Working…' : message}</p>
          <Button variant="quiet" onClick={onClose} disabled={busy}>
            Close
          </Button>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
