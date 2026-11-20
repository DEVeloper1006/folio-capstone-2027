/**
 * Save one page through a native destination picker. Atomically replace the chosen file and keep graph attachments in a new companion directory.
 *
 * @file
 */
const fs = require('node:fs/promises')
const path = require('node:path')
const { randomUUID } = require('node:crypto')

/** Restrict exports to the trusted notebook window and paths selected by the user. */
function installExport(ipcMain, dialog, getWindow) {
  let busy = false
  /** Validate the payload before opening a native picker, then save without exposing arbitrary filesystem access. */
  async function save(event, request) {
    const window = getWindow()
    if (event.sender !== window?.webContents || event.senderFrame !== event.sender.mainFrame || !event.senderFrame.url.startsWith('folio://app/')) throw new Error('Untrusted export sender')
    if (busy) throw new Error('An export is already in progress.')
    if (!request || !['pdf', 'md'].includes(request.format) || typeof request.title !== 'string' || request.title.length > 10000 || typeof request.markdown !== 'string' || Buffer.byteLength(request.markdown) > 16 * 1024 * 1024 || !Array.isArray(request.images) || request.images.length > 1000)
      throw new Error('Invalid export document.')
    const images = []
    let size = 0
    for (const image of request.images) {
      if (!image || typeof image.token !== 'string' || !/^folio-image-[0-9a-f-]{36}$/.test(image.token) || typeof image.data !== 'string' || !image.data.startsWith('data:image/png;base64,')) throw new Error('Invalid graph image.')
      size += image.data.length
      if (size > 128 * 1024 * 1024) throw new Error('Graph images exceed the 128 MB export limit.')
      const bytes = Buffer.from(image.data.slice(22), 'base64')
      if (!bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('Graph image is not a PNG.')
      images.push({ token: image.token, bytes })
    }
    busy = true
    let temporary
    let assets
    let saved = false
    try {
      const title =
        request.title
          .replace(/[\x00-\x1f/\\:]/g, '-')
          .replace(/^\.+/, '')
          .slice(0, 120) || 'Untitled'
      const result = await dialog.showSaveDialog(window, { defaultPath: `${title}.${request.format}`, filters: [{ name: request.format === 'pdf' ? 'PDF document' : 'Markdown document', extensions: [request.format] }] })
      if (result.canceled || !result.filePath) return { canceled: true }
      const file = result.filePath
      let content
      if (request.format === 'pdf') content = await window.webContents.printToPDF({ printBackground: true, preferCSSPageSize: true, pageSize: 'A4' })
      else {
        content = request.markdown
        if (images.length) {
          assets = await fs.mkdtemp(path.join(path.dirname(file), path.basename(file, path.extname(file)) + '-assets-'))
          for (let index = 0; index < images.length; index++) {
            const name = `graph-${index + 1}.png`
            await fs.writeFile(path.join(assets, name), images[index].bytes, { flag: 'wx' })
            content = content.replaceAll(images[index].token, `${encodeURIComponent(path.basename(assets))}/${name}`)
          }
        }
      }
      temporary = path.join(path.dirname(file), `.${path.basename(file)}.${randomUUID()}.tmp`)
      await fs.writeFile(temporary, content, { flag: 'wx' })
      await fs.rename(temporary, file)
      saved = true
      return { canceled: false, path: file }
    } finally {
      busy = false
      if (temporary) await fs.rm(temporary, { force: true })
      if (assets && !saved) await fs.rm(assets, { recursive: true, force: true })
    }
  }
  ipcMain.handle('folio:export', save)
}
module.exports = { installExport }
