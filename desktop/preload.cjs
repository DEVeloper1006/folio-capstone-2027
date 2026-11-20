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
/** Request structured help from the fixed local model service. */
function assist(id, body) {
  return ipcRenderer.invoke('folio:assist', id, body)
}
/** Cancel a stale suggestion without exposing other IPC channels. */
function cancelCompletion(id) {
  ipcRenderer.send('folio:cancel-completion', id)
}
/** Load the fixed settings file, creating it only when absent. */
function readSettings(initial) {
  return ipcRenderer.invoke('folio:settings-read', initial)
}
/** Replace settings only if the editor still holds the current disk revision. */
function saveSettings(text, expected) {
  return ipcRenderer.invoke('folio:settings-save', text, expected)
}
/** Show the settings file in the system file manager. */
function revealSettings() {
  return ipcRenderer.invoke('folio:settings-reveal')
}
/** Subscribe without exposing IPC events or arbitrary channels. */
function onSettingsChanged(callback) {
  /** Forward only a change notification. */
  function changed() {
    callback()
  }
  ipcRenderer.on('folio:settings-changed', changed)
  /** Stop notifying an unmounted settings owner. */
  function unsubscribe() {
    ipcRenderer.removeListener('folio:settings-changed', changed)
  }
  return unsubscribe
}
/** Save a page through the native export picker. */
function exportPage(request) {
  return ipcRenderer.invoke('folio:export', request)
}
/** Save synchronously so failed disk writes never publish an unsaved document in the editor. */
function notebook(operation, payload) {
  const response = ipcRenderer.sendSync('folio:notebook', operation, payload)
  if (response.error) throw new Error(response.error)
  return response.result
}
/** Load the active root, migrating the original notebook only once. */
function loadNotebook(initial) {
  return notebook('load', initial)
}
/** Re-read external Markdown edits and filesystem organization. */
function reloadNotebook() {
  return notebook('reload')
}
/** Persist a page through the journaled filesystem writer. */
function saveNotebookPage(page) {
  return notebook('page', page)
}
/** Persist folder and page organization through the same writer. */
function saveNotebookList(list) {
  return notebook('list', list)
}
/** Reveal the current root in Finder. */
function revealRoots() {
  return ipcRenderer.invoke('folio:roots-reveal')
}
/** Select a local Markdown folder. */
function chooseRoots() {
  return ipcRenderer.invoke('folio:roots-choose')
}
/** Save all editable notebook data to a portable backup. */
function backupRoots() {
  return ipcRenderer.invoke('folio:roots-backup')
}
/** Restore a selected backup into a new folder. */
function restoreRoots() {
  return ipcRenderer.invoke('folio:roots-restore')
}
contextBridge.exposeInMainWorld('folioDesktop', {
  loadNotebook,
  reloadNotebook,
  saveNotebookPage,
  saveNotebookList,
  revealRoots,
  chooseRoots,
  backupRoots,
  restoreRoots,
  exportPage,
  complete,
  assist,
  cancelCompletion,
  readSettings,
  saveSettings,
  revealSettings,
  onSettingsChanged,
})
