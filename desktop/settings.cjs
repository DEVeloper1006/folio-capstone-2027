/**
 * Read and atomically replace Folio's one settings file. Keep the path fixed, reject stale saves, and notify the renderer when an external editor changes the file.
 *
 * @file
 */
const fs = require('node:fs')
const path = require('node:path')

/** Install narrowly scoped settings operations for the current trusted window. */
function installSettings(app, ipcMain, shell, getWindow) {
  const file = path.join(app.getPath('userData'), 'settings.json')
  /** Verify the caller is Folio's current top-level document. */
  function trusted(event) {
    const window = getWindow()
    if (event.sender !== window?.webContents || event.senderFrame !== event.sender.mainFrame || !event.senderFrame.url.startsWith('folio://app/')) throw new Error('Untrusted settings sender')
  }
  /** Bound disk and IPC input without executing configuration code. */
  function validate(text) {
    if (typeof text !== 'string' || Buffer.byteLength(text) > 131072) throw new Error('Settings must be at most 128 KB.')
    const value = JSON.parse(text)
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Settings must be a JSON object.')
  }
  /** Read raw text even when invalid so the user can repair it. */
  function read() {
    if (fs.statSync(file).size > 131072) throw new Error('Settings must be at most 128 KB. Edit the file externally to reduce its size.')
    return { path: file, text: fs.readFileSync(file, 'utf8') }
  }
  /** Create the file once from the user's existing theme; never replace an existing file. */
  function load(event, initial) {
    trusted(event)
    validate(initial)
    fs.mkdirSync(path.dirname(file), { recursive: true })
    try {
      fs.writeFileSync(file, initial, { flag: 'wx', mode: 0o600 })
    } catch (error) {
      if (error.code !== 'EEXIST') throw error
    }
    return read()
  }
  /** Compare the source revision immediately before a same-directory atomic replacement. */
  function save(event, text, expected) {
    trusted(event)
    validate(text)
    if (read().text !== expected) throw new Error('The settings file changed outside this editor. Reload it before saving to avoid overwriting those changes.')
    const temporary = file + '.tmp'
    try {
      fs.writeFileSync(temporary, text, { mode: 0o600 })
      fs.renameSync(temporary, file)
    } finally {
      if (fs.existsSync(temporary)) fs.unlinkSync(temporary)
    }
    return read()
  }
  /** Reveal only the settings file, never an arbitrary renderer-supplied path. */
  function reveal(event) {
    trusted(event)
    shell.showItemInFolder(file)
  }
  /** Ask the renderer to validate and apply external saves, including atomic editor replacements. */
  function changed() {
    getWindow()?.webContents.send('folio:settings-changed')
  }
  /** Release the polling watcher on application exit. */
  function stop() {
    fs.unwatchFile(file, changed)
  }
  ipcMain.handle('folio:settings-read', load)
  ipcMain.handle('folio:settings-save', save)
  ipcMain.handle('folio:settings-reveal', reveal)
  fs.watchFile(file, { interval: 750, persistent: false }, changed)
  app.on('will-quit', stop)
}
module.exports = { installSettings }
