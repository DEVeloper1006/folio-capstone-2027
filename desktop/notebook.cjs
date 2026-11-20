/**
 * Store Roots as real Markdown folders with hidden Folio metadata. Journal writes, preserve the original browser notebook during migration, and reject stale writes over external edits.
 *
 * @file
 */
const fs = require('node:fs')
const path = require('node:path')
const { randomUUID, createHash } = require('node:crypto')
const { parseNotebook } = require('./notebook-format.cjs')

/** Hash exact bytes to detect external edits before replacing a document. */
function hash(value) {
  return createHash('sha256').update(value).digest('hex')
}
/** Replace a file using a same-directory temporary file. */
function atomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const temporary = file + '.' + randomUUID() + '.tmp'
  try {
    fs.writeFileSync(temporary, data, { flag: 'wx' })
    fs.renameSync(temporary, file)
  } finally {
    fs.rmSync(temporary, { force: true })
  }
}
/** Require names that remain ordinary, visible files on all supported platforms. */
function name(value) {
  if (typeof value !== 'string' || !value.trim() || value !== value.trim() || value.length > 180 || /[<>:"/\\|?*\x00-\x1f]/.test(value) || value.startsWith('.') || /[. ]$/.test(value)) throw new Error('Use a name without slashes, reserved filename characters, or leading/trailing dots and spaces.')
  return value
}
/** Keep editable page titles usable while deriving a portable filename from an unfinished title. */
function pageName(value) {
  return (
    value
      .replace(/[<>:"/\\|?*\x00-\x1f]/g, '-')
      .replace(/^\.+/, '')
      .replace(/[. ]+$/, '')
      .trim()
      .slice(0, 180) || 'Untitled'
  )
}
/** Resolve a vault-relative path without following symlinks or escaping the root. */
function inside(root, relative) {
  if (typeof relative !== 'string' || !relative || path.isAbsolute(relative)) throw new Error('Invalid Roots path.')
  const file = path.resolve(root, relative)
  if (!file.startsWith(root + path.sep)) throw new Error('Path escapes Roots.')
  let cursor = root
  for (const part of path.relative(root, file).split(path.sep)) {
    cursor = path.join(cursor, part)
    if (fs.existsSync(cursor) && fs.lstatSync(cursor).isSymbolicLink()) throw new Error('Roots does not follow symbolic links.')
  }
  return file
}
/** Generate paths from folder identities, detecting filename collisions before writing anything. */
function locations(notebook) {
  const folders = {}
  const pages = {}
  const occupied = new Set()
  /** Resolve parents before children, independent of sidebar insertion order. */
  function folder(id) {
    if (folders[id]) return folders[id]
    /** Resolve one stable folder identity. */
    function matches(entry) {
      return entry.folderId === id
    }
    const item = notebook.list.folders.find(matches)
    if (!item) throw new Error('Missing folder.')
    return (folders[id] = path.join(item.parentId ? folder(item.parentId) : '', name(item.title)))
  }
  for (const item of notebook.list.folders) folder(item.folderId)
  for (const relative of Object.values(folders)) {
    if (occupied.has(relative.toLocaleLowerCase())) throw new Error('Two folders have the same name in this location.')
    occupied.add(relative.toLocaleLowerCase())
  }
  for (const item of notebook.list.pages) {
    const relative = path.join(item.folderId ? folder(item.folderId) : '', pageName(item.title) + '.md')
    if (occupied.has(relative.toLocaleLowerCase())) throw new Error('A page with this filename already exists in this folder. Rename it first.')
    occupied.add(relative.toLocaleLowerCase())
    pages[item.pageId] = relative
  }
  return { folders, pages }
}
/** Write readable Markdown with invisible identity markers for Folio-specific block metadata. */
function markdown(page, relative) {
  const pieces = [`<!-- folio:page ${page.pageId} -->`]
  for (const cell of page.cells) {
    let source
    if (cell.kind === 'markdown') source = cell.markdown
    else if (cell.kind === 'math') source = `${cell.caption || ''}\n\n$$\n${cell.latex}\n$$`
    else {
      const image = path
        .relative(path.dirname(relative), path.join('assets', `${page.pageId}-${cell.cellId}.png`))
        .split(path.sep)
        .map(encodeURIComponent)
        .join('/')
      source = `![${cell.graph.dimension.toUpperCase()} graph](${image})`
    }
    pieces.push(`<!-- folio:cell ${cell.cellId} -->\n\n${source}`)
  }
  return pieces.join('\n\n') + '\n'
}
/** Read external edits while retaining block identity, nesting, modes, and graph metadata. */
function editedPage(source, original, title, relative) {
  if (!original) return { pageId: randomUUID(), title, cells: [{ cellId: randomUUID(), kind: 'markdown', markdown: source }], pageMetadata: { width: 'narrow', cellSpacingPx: 16, editorMode: 'rich' } }
  const matches = [...source.matchAll(/^<!-- folio:cell ([^\r\n]+) -->\r?$/gm)]
  if (!matches.length && original.cells.length) throw new Error(`The Folio block markers were removed from ${title}. Restore the markers or import the text as a new .md file.`)
  const cells = []
  const prefix = source
    .slice(0, matches[0]?.index ?? source.length)
    .replace(/^<!-- folio:page [^\r\n]+ -->\r?\n?/, '')
    .trim()
  if (prefix) cells.push({ cellId: randomUUID(), kind: 'markdown', markdown: prefix })
  for (let index = 0; index < matches.length; index++) {
    const match = matches[index]
    /** Resolve a marker against the saved cell metadata. */
    function sameCell(item) {
      return item.cellId === match[1]
    }
    const cell = original.cells.find(sameCell)
    if (!cell) throw new Error(`Unknown block marker in ${title}. Keep Folio's identity comments unchanged.`)
    const content = source
      .slice(match.index + match[0].length, matches[index + 1]?.index ?? source.length)
      .replace(/^\r?\n\r?\n/, '')
      .replace(/\r?\n\r?\n$/, '')
      .replace(/\r?\n$/, '')
    if (cell.kind === 'markdown') cells.push({ ...cell, markdown: content })
    else if (cell.kind === 'math') {
      const formula = /^(.*?)\n\n\$\$\r?\n([\s\S]*?)\r?\n\$\$$/s.exec(content)
      if (!formula) throw new Error(`Keep the display-math delimiters in ${title}, or edit this math block in Folio.`)
      cells.push({ ...cell, caption: formula[1] || undefined, latex: formula[2] })
    } else {
      const rendered = markdown({ pageId: original.pageId, cells: [cell] }, relative)
      const expected = rendered.slice(rendered.indexOf(`<!-- folio:cell ${cell.cellId} -->`) + `<!-- folio:cell ${cell.cellId} -->`.length).trim()
      if (content.trim() !== expected) throw new Error(`The graph link in ${title} changed. Edit captured graphs in Folio to preserve their source and view.`)
      cells.push(cell)
    }
  }
  return { ...original, title, cells }
}
/** Create parent directories before children. */
function shortestPathFirst(a, b) {
  return a.length - b.length
}
/** Remove children before their now-empty parent directories. */
function longestPathFirst(a, b) {
  return b.length - a.length
}
/** Own one selected local root and expose only validated notebook operations. */
function installNotebook(app, ipcMain, dialog, shell, getWindow) {
  const preference = path.join(app.getPath('userData'), 'roots.json')
  let root = fs.existsSync(preference) ? JSON.parse(fs.readFileSync(preference, 'utf8')).path : path.join(app.getPath('documents'), 'Folio')
  root = path.resolve(root)
  let state
  let drafts = new Map()
  /** Resolve metadata within the currently selected local folder. */
  function metadata(file) {
    return inside(root, '.folio/' + file)
  }
  /** Ensure only the trusted Folio frame can reach local files. */
  function trusted(event) {
    const window = getWindow()
    if (event.sender !== window?.webContents || event.senderFrame !== event.sender.mainFrame || !event.senderFrame.url.startsWith('folio://app/')) throw new Error('Untrusted notebook sender.')
  }
  /** Roll back an interrupted transaction before any document is read. */
  function recover() {
    const journal = metadata('transaction.json')
    if (!fs.existsSync(journal)) return
    const before = JSON.parse(fs.readFileSync(journal, 'utf8'))
    for (const relative of before.folders) fs.mkdirSync(inside(root, relative), { recursive: true })
    for (const [relative, value] of Object.entries(before.files)) {
      const file = inside(root, relative)
      if (value === null) fs.rmSync(file, { force: true })
      else atomic(file, Buffer.from(value, 'base64'))
    }
    for (const relative of before.createdFolders.reverse()) {
      const folder = inside(root, relative)
      if (fs.existsSync(folder) && fs.readdirSync(folder).length === 0) fs.rmdirSync(folder)
    }
    fs.rmSync(journal)
  }
  /** Scan real folders and Markdown files, incorporating external changes by stable page identity. */
  function scan() {
    recover()
    if (!fs.existsSync(metadata('notebook.json'))) return undefined
    const previous = JSON.parse(fs.readFileSync(metadata('notebook.json'), 'utf8'))
    previous.notebook = parseNotebook(JSON.stringify(previous.notebook))
    const pages = [],
      entries = [],
      folders = [],
      paths = {},
      folderPaths = {},
      hashes = {}
    /** Index original metadata by stable identity. */
    function pageEntry(page) {
      return [page.pageId, page]
    }
    const known = new Map(previous.notebook.pages.map(pageEntry))
    /** Visit only ordinary Markdown files and directories; metadata and attachments stay out of the page tree. */
    function visit(relative, parentId) {
      const directory = relative ? inside(root, relative) : root
      for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        if (entry.name.startsWith('.') || entry.isSymbolicLink()) continue
        const child = path.join(relative, entry.name)
        if (entry.isDirectory()) {
          /** Keep folder identity while its path remains unchanged. */
          function sameFolder(id) {
            return previous.folders[id] === child
          }
          const oldId = Object.keys(previous.folders).find(sameFolder)
          const folderId = oldId || randomUUID()
          const folderStart = folders.length
          const pageStart = pages.length
          folders.push({ folderId, title: entry.name, parentId })
          folderPaths[folderId] = child
          visit(child, folderId)
          // Hide generated attachments only; explicit folders and Markdown notes named assets remain visible.
          if (!relative && entry.name === 'assets' && !oldId && pages.length === pageStart) {
            for (const unused of folders.splice(folderStart)) delete folderPaths[unused.folderId]
          }
        } else if (entry.isFile() && entry.name.endsWith('.md')) {
          const file = inside(root, child)
          if (fs.statSync(file).size > 16 * 1024 * 1024) throw new Error(`${child} exceeds the 16 MB page limit.`)
          const source = fs.readFileSync(file, 'utf8')
          const headerId = /^<!-- folio:page ([^\r\n]+) -->/.exec(source)?.[1]
          /** Reuse identity for Markdown imported without Folio comments. */
          function samePage(id) {
            return previous.pages[id] === child
          }
          const oldId = headerId || Object.keys(previous.pages).find(samePage)
          const original = known.get(oldId)
          const title = original && previous.pages[oldId] === child ? original.title : entry.name.slice(0, -3)
          const page = original && previous.hashes[oldId] === hash(source) ? { ...original, title } : editedPage(source, original, title, child)
          if (paths[page.pageId]) throw new Error(`Duplicate Folio page identity in ${child}. Import copied text without its Folio comments.`)
          pages.push(page)
          entries.push({ pageId: page.pageId, title, folderId: parentId })
          paths[page.pageId] = child
          hashes[page.pageId] = hash(source)
        }
      }
    }
    visit('', undefined)
    if (!pages.length) throw new Error('Roots contains no Markdown pages. Add a .md file before reloading.')
    /** Retain the user's sidebar order across filesystem scans. */
    function orderEntry(page, index) {
      return [page.pageId, index]
    }
    const order = new Map(previous.notebook.list.pages.map(orderEntry))
    /** Place newly discovered pages after existing ones. */
    function pageOrder(a, b) {
      return (order.get(a.pageId) ?? Infinity) - (order.get(b.pageId) ?? Infinity)
    }
    entries.sort(pageOrder)
    const openPageId = paths[previous.notebook.list.openPageId] ? previous.notebook.list.openPageId : entries[0].pageId
    const notebook = parseNotebook(JSON.stringify({ version: 1, list: { pages: entries, folders, openPageId }, pages }))
    state = { notebook, pages: paths, folders: folderPaths, hashes }
    atomic(metadata('notebook.json'), JSON.stringify(state))
    return notebook
  }
  /** Commit changed files with rollback data; refuse external edits and destination collisions before mutation. */
  function commit(notebook) {
    notebook = parseNotebook(JSON.stringify(notebook))
    const next = locations(notebook)
    const changes = new Map()
    const hashes = {}
    for (const [id, relative] of Object.entries(state?.pages || {})) {
      const file = inside(root, relative)
      if (!fs.existsSync(file) || hash(fs.readFileSync(file)) !== state.hashes[id]) throw new Error('A Markdown file changed outside Folio. Reload Roots before saving; the external edit was not overwritten.')
      if (next.pages[id] !== relative) changes.set(relative, null)
    }
    for (const page of notebook.pages) {
      const relative = next.pages[page.pageId]
      const file = inside(root, relative)
      if (fs.existsSync(file) && !Object.values(state?.pages || {}).includes(relative)) throw new Error(`The file ${relative} already exists. Reload Roots before saving.`)
      const source = markdown(page, relative)
      hashes[page.pageId] = hash(source)
      if (!fs.existsSync(file) || hash(fs.readFileSync(file)) !== hashes[page.pageId]) changes.set(relative, Buffer.from(source))
      for (const cell of page.cells)
        if (cell.kind === 'graph') {
          const image = path.join('assets', `${page.pageId}-${cell.cellId}.png`)
          const bytes = Buffer.from(cell.snapshot.image.slice(22), 'base64')
          const target = inside(root, image)
          if (!fs.existsSync(target) || hash(fs.readFileSync(target)) !== hash(bytes)) changes.set(image, bytes)
        }
    }
    const nextState = { notebook, pages: next.pages, folders: next.folders, hashes }
    changes.set('.folio/notebook.json', Buffer.from(JSON.stringify(nextState)))
    const before = {}
    for (const relative of changes.keys()) {
      const file = inside(root, relative)
      before[relative] = fs.existsSync(file) ? fs.readFileSync(file).toString('base64') : null
    }
    const oldFolders = Object.values(state?.folders || {})
    const createdFolders = []
    for (const relative of Object.values(next.folders)) if (!fs.existsSync(inside(root, relative))) createdFolders.push(relative)
    createdFolders.sort(shortestPathFirst)
    atomic(metadata('transaction.json'), JSON.stringify({ files: before, folders: oldFolders, createdFolders }))
    try {
      for (const relative of Object.values(next.folders)) fs.mkdirSync(inside(root, relative), { recursive: true })
      for (const [relative, bytes] of changes) {
        const file = inside(root, relative)
        if (bytes === null) {
          // Retain deleted or relocated source files for recovery without cluttering Roots.
          if (fs.existsSync(file)) atomic(metadata(`history/${randomUUID()}.md`), fs.readFileSync(file))
          fs.rmSync(file, { force: true })
        } else atomic(file, bytes)
      }
      for (const relative of oldFolders.sort(longestPathFirst))
        if (!Object.values(next.folders).includes(relative)) {
          const folder = inside(root, relative)
          if (fs.existsSync(folder) && fs.readdirSync(folder).length === 0) fs.rmdirSync(folder)
        }
      fs.rmSync(metadata('transaction.json'))
      state = nextState
    } catch (error) {
      recover()
      throw error
    }
    atomic(preference, JSON.stringify({ path: root }))
  }
  /** Initialize from the untouched legacy notebook, or read the already selected folder. */
  function load(initial) {
    fs.mkdirSync(root, { recursive: true })
    const existing = scan()
    if (existing) return existing
    const notebook = parseNotebook(initial)
    const files = fs.readdirSync(root)
    /** Refuse to migrate over an existing visible file or folder. */
    function visible(entry) {
      return !entry.startsWith('.')
    }
    if (files.some(visible)) throw new Error(`The folder ${root} already contains files. Choose an existing Roots folder or an empty folder.`)
    state = undefined
    commit(notebook)
    atomic(metadata('migration-backup.json'), initial)
    return notebook
  }
  /** Bound synchronous requests to storage operations so callers save before publishing React state. */
  function request(event, operation, payload) {
    try {
      trusted(event)
      let result
      if (operation === 'load') result = { notebook: load(payload), path: root }
      else if (operation === 'reload') result = { notebook: scan(), path: root }
      else if (operation === 'page') {
        if (!state) throw new Error('Roots is not loaded.')
        /** Replace only the edited page. */
        function replace(page) {
          return page.pageId === payload.pageId ? payload : page
        }
        /** Distinguish new pages awaiting their sidebar insertion. */
        function matches(page) {
          return page.pageId === payload.pageId
        }
        const pages = state.notebook.pages.map(replace)
        if (!state.notebook.pages.some(matches)) {
          drafts.set(payload.pageId, payload)
          result = true
        } else {
          commit({ ...state.notebook, pages })
          result = true
        }
      } else if (operation === 'list') {
        if (!state) throw new Error('Roots is not loaded.')
        /** Resolve every listed page before the transaction starts. */
        function listedPage(entry) {
          /** Match the persisted page by identity. */
          function matches(page) {
            return page.pageId === entry.pageId
          }
          return drafts.get(entry.pageId) || state.notebook.pages.find(matches)
        }
        const pages = payload.pages.map(listedPage)
        commit({ version: 1, list: payload, pages })
        drafts.clear()
        result = true
      } else throw new Error('Unknown notebook operation.')
      event.returnValue = { result }
    } catch (error) {
      event.returnValue = { error: error.message }
    }
  }
  /** Reveal the folder containing the user's actual Markdown files. */
  async function reveal(event) {
    trusted(event)
    const error = await shell.openPath(root)
    if (error) throw new Error(error)
  }
  /** Select an existing Folio root, a Markdown folder, or an empty folder without moving the previous one. */
  async function choose(event) {
    trusted(event)
    const result = await dialog.showOpenDialog(getWindow(), { title: 'Open Roots folder', properties: ['openDirectory', 'createDirectory'] })
    if (result.canceled) return false
    const selected = fs.realpathSync(result.filePaths[0])
    const oldRoot = root,
      oldState = state
    try {
      root = selected
      state = undefined
      drafts.clear()
      if (!fs.existsSync(metadata('notebook.json'))) {
        const empty = { pageId: randomUUID(), title: 'Untitled', cells: [], pageMetadata: { width: 'narrow', editorMode: 'rich', cellSpacingPx: 16 } }
        const initial = { version: 1, list: { pages: [{ pageId: empty.pageId, title: empty.title }], folders: [], openPageId: empty.pageId }, pages: [empty] }
        const seed = { notebook: initial, pages: {}, folders: {}, hashes: {} }
        atomic(metadata('notebook.json'), JSON.stringify(seed))
        try {
          scan()
        } catch (error) {
          if (error.message !== 'Roots contains no Markdown pages. Add a .md file before reloading.') throw error
          state = undefined
          commit(initial)
        }
      } else scan()
      atomic(preference, JSON.stringify({ path: root }))
      return true
    } catch (error) {
      root = oldRoot
      state = oldState
      throw error
    }
  }
  /** Export the complete editable notebook, including closed pages and graph sources. */
  async function backup(event) {
    trusted(event)
    const notebook = scan()
    if (!notebook) throw new Error('Roots is not loaded.')
    const result = await dialog.showSaveDialog(getWindow(), { defaultPath: 'Folio-backup.folio', filters: [{ name: 'Folio backup', extensions: ['folio'] }] })
    if (result.canceled || !result.filePath) return { canceled: true }
    atomic(result.filePath, JSON.stringify(notebook, null, 2))
    return { canceled: false, path: result.filePath }
  }
  /** Restore into a new folder, leaving the current Roots and all its files untouched. */
  async function restore(event) {
    trusted(event)
    const chosen = await dialog.showOpenDialog(getWindow(), { title: 'Restore Folio backup', properties: ['openFile'], filters: [{ name: 'Folio backup', extensions: ['folio'] }] })
    if (chosen.canceled) return false
    if (fs.statSync(chosen.filePaths[0]).size > 128 * 1024 * 1024) throw new Error('Backup exceeds 128 MB.')
    const notebook = parseNotebook(fs.readFileSync(chosen.filePaths[0], 'utf8'))
    const destination = await dialog.showOpenDialog(getWindow(), { title: 'Choose parent folder for restored Roots', properties: ['openDirectory', 'createDirectory'] })
    if (destination.canceled) return false
    const oldRoot = root,
      oldState = state
    root = fs.mkdtempSync(path.join(destination.filePaths[0], 'Folio-restored-'))
    state = undefined
    try {
      commit(notebook)
      drafts.clear()
      return true
    } catch (error) {
      root = oldRoot
      state = oldState
      throw error
    }
  }
  ipcMain.on('folio:notebook', request)
  ipcMain.handle('folio:roots-reveal', reveal)
  ipcMain.handle('folio:roots-choose', choose)
  ipcMain.handle('folio:roots-backup', backup)
  ipcMain.handle('folio:roots-restore', restore)
}
module.exports = { installNotebook }
