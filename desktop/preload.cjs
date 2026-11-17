/**
 * Expose the desktop completion transport without sharing Node or raw IPC with the editor.
 *
 * @file
 */
const { contextBridge, ipcRenderer } = require('electron')

/** Send the editor's validated request to the main process. */
function complete(id, body) {
  return ipcRenderer.invoke('folio:complete', id, body)
}
/** Cancel a stale suggestion without exposing other IPC channels. */
function cancelCompletion(id) {
  ipcRenderer.send('folio:cancel-completion', id)
}
contextBridge.exposeInMainWorld('folioDesktop', { complete, cancelCompletion })
