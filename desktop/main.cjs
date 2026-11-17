/**
 * Run the bundled Folio notebook on a secure local protocol and handle completion requests.
 *
 * @file
 */
const { app, BrowserWindow, ipcMain, Menu, net, protocol, shell } = require('electron')
const { existsSync } = require('node:fs')
const path = require('node:path')
const { pathToFileURL } = require('node:url')

app.setName('Folio')
protocol.registerSchemesAsPrivileged([{ scheme: 'folio', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true } }])
let mainWindow
const pendingCompletions = new Map()

/** Resolve bundled assets and fall back to the SPA shell for client routes. */
async function serve(request) {
  const url = new URL(request.url)
  if (url.host !== 'app' || request.method !== 'GET') return new Response(null, { status: 404 })
  let name
  try {
    name = decodeURIComponent(url.pathname)
  } catch {
    return new Response(null, { status: 400 })
  }
  const root = path.join(__dirname, 'renderer')
  const file = path.resolve(root, '.' + name)
  if (!file.startsWith(root + path.sep) && file !== root) return new Response(null, { status: 403 })
  const asset = path.extname(file) ? file : path.join(root, '_shell.html')
  if (!existsSync(asset)) return new Response(null, { status: 404 })
  const response = await net.fetch(pathToFileURL(asset).href)
  const headers = new Headers(response.headers)
  headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'")
  return new Response(response.body, { status: response.status, headers })
}

/** Forward only bounded text-completion requests from Folio's own top-level renderer. */
async function complete(event, id, body) {
  if (event.sender !== mainWindow?.webContents || event.senderFrame !== event.sender.mainFrame || !event.senderFrame.url.startsWith('folio://app/')) throw new Error('Untrusted completion sender')
  if (typeof id !== 'string' || id.length > 64 || pendingCompletions.has(id)) throw new Error('Invalid completion ID')
  if (typeof body !== 'string' || body.length > 64000) throw new Error('Invalid completion body')
  const payload = JSON.parse(body)
  /** Accept only plain text messages used by the autocomplete prompt. */
  function invalidMessage(message) {
    return !message || !['system', 'user'].includes(message.role) || typeof message.content !== 'string'
  }
  if (!Array.isArray(payload.messages) || payload.messages.length > 4 || payload.messages.some(invalidMessage)) throw new Error('Invalid completion messages')
  const key = process.env.OPENROUTER_API_KEY
  if (!key) return { status: 503, body: '{}' }
  const controller = new AbortController()
  pendingCompletions.set(id, controller)
  /** Stop provider work when the request exceeds the desktop deadline. */
  function expire() {
    controller.abort()
  }
  const timeout = setTimeout(expire, 30000)
  try {
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'deepseek/deepseek-v4.1-flash', temperature: 0.2, max_tokens: 160, reasoning: { enabled: false }, messages: payload.messages }),
      signal: controller.signal,
    })
    return { status: response.status, body: await response.text() }
  } catch {
    return { status: 502, body: '{}' }
  } finally {
    clearTimeout(timeout)
    pendingCompletions.delete(id)
  }
}

/** Keep external links outside the notebook and reject arbitrary schemes. */
function openExternal(url) {
  if (/^https?:\/\//.test(url)) void shell.openExternal(url)
}

/** Create one isolated editor window and retain native edit shortcuts. */
function createWindow() {
  mainWindow = new BrowserWindow({ width: 1280, height: 900, title: 'Folio', webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true } })
  /** Open requested links in the browser instead of creating privileged windows. */
  function openWindow({ url }) {
    openExternal(url)
    return { action: 'deny' }
  }
  mainWindow.webContents.setWindowOpenHandler(openWindow)
  /** Keep the editor on its local origin and delegate external web navigation. */
  function navigate(event, url) {
    if (!url.startsWith('folio://app/')) {
      event.preventDefault()
      openExternal(url)
    }
  }
  mainWindow.webContents.on('will-navigate', navigate)
  /** Cancel pending suggestions when their renderer is destroyed. */
  function close() {
    for (const controller of pendingCompletions.values()) controller.abort()
    mainWindow = undefined
  }
  mainWindow.on('closed', close)
  void mainWindow.loadURL('folio://app/')
}

/** Install the protocol and desktop handlers before opening the first window. */
async function ready() {
  protocol.handle('folio', serve)
  ipcMain.handle('folio:complete', complete)
  /** Cancel only requests owned by the current top-level notebook. */
  function cancel(event, id) {
    if (event.sender === mainWindow?.webContents && event.senderFrame === event.sender.mainFrame) pendingCompletions.get(id)?.abort()
  }
  ipcMain.on('folio:cancel-completion', cancel)
  const template = [{ role: 'fileMenu' }, { role: 'editMenu' }, { role: 'viewMenu' }, { role: 'windowMenu' }]
  if (process.platform === 'darwin') template.unshift({ role: 'appMenu' })
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
  createWindow()
  /** Reopen the notebook when macOS activates an application without a window. */
  function activate() {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  }
  app.on('activate', activate)
}
if (app.requestSingleInstanceLock()) {
  /** Focus the existing editor rather than opening a second storage writer. */
  function secondInstance() {
    if (!mainWindow && app.isReady()) createWindow()
    if (mainWindow?.isMinimized()) mainWindow.restore()
    mainWindow?.show()
    mainWindow?.focus()
  }
  app.on('second-instance', secondInstance)
  app.whenReady().then(ready)
} else app.quit()
/** Keep standard macOS background behavior and quit on other platforms. */
function allClosed() {
  if (process.platform !== 'darwin') app.quit()
}
app.on('window-all-closed', allClosed)
