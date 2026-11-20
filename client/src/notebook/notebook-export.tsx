/**
 * Export a frozen page as rendered PDF or portable Markdown with graph attachments. Reuse notebook renderers so exported notation matches the document.
 *
 * @file
 */
import { useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Dialog } from '@base-ui/react/dialog'
import { Button } from '../component-library'
import { MarkdownDocument } from '../components/markdown-cell'
import { MathPreview } from '../component-library/math-preview'
import { blockDepth } from './notebook-blocks'
import { cellSource } from './notebook-cells'
import type { NotebookCell } from './notebook-cells'
import type { Page } from './page'
import './notebook-export.css'

export interface PageExportRequest {
  format: 'pdf' | 'md'
  title: string
  markdown: string
  images: { token: string; data: string }[]
}
/** Preserve Markdown, LaTeX, nested block order, and each graph's captured image and equations. */
export function markdownExport(page: Page): PageExportRequest {
  const images: PageExportRequest['images'] = []
  const parts = ['# ' + (page.title || 'Untitled').replace(/[\\`*_{}[\]<>#!|]/g, '\\$&').replace(/\r?\n/g, ' ')]
  for (const cell of page.cells) {
    let text = cell.kind === 'markdown' ? cell.markdown : cell.kind === 'math' ? `${cell.caption || ''}\n\n$$\n${cell.latex}\n$$` : ''
    if (cell.kind === 'graph') {
      const token = `folio-image-${crypto.randomUUID()}`
      images.push({ token, data: cell.snapshot.image })
      /** Keep equations literal even when they contain Markdown delimiters. */
      function codeLine(line: string) {
        return '    ' + line
      }
      text = `![${cell.graph.dimension.toUpperCase()} graph](${token})\n\n${cellSource(cell).split('\n').map(codeLine).join('\n')}`
    }
    /** Represent nested blocks as portable Markdown block quotes. */
    function nestedLine(line: string) {
      return '> '.repeat(blockDepth(cell)) + line
    }
    parts.push(text.trim().split('\n').map(nestedLine).join('\n'))
  }
  return { format: 'md', title: page.title || 'Untitled', markdown: parts.join('\n\n') + '\n', images }
}
/** Hold the selected page steady while a native save dialog is open. */
export function NotebookExport({ page, onClose }: { page: Page; onClose: () => void }) {
  const paper = useRef<HTMLElement>(null)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  /** Keep the printable page mounted until the native operation finishes. */
  function close(open: boolean) {
    if (!open && !busy) onClose()
  }
  /** Render the same stored content without editing controls or side panels. */
  function renderCell(cell: NotebookCell) {
    return (
      <section key={cell.cellId} style={{ marginLeft: blockDepth(cell) * 20 }}>
        {cell.kind === 'markdown' ? (
          <MarkdownDocument markdown={cell.markdown} />
        ) : cell.kind === 'math' ? (
          <>
            <MarkdownDocument markdown={cell.caption || ''} />
            <MathPreview latex={cell.latex} />
          </>
        ) : (
          <figure>
            <img src={cell.snapshot.image} alt={`${cell.graph.dimension.toUpperCase()} graph`} />
            <figcaption>{cellSource(cell)}</figcaption>
          </figure>
        )}
      </section>
    )
  }
  /** Wait for fonts and images before asking Electron to capture the print document. */
  async function save(format: 'pdf' | 'md') {
    setBusy(true)
    setMessage('')
    try {
      if (!window.folioDesktop) throw new Error('Open Folio desktop to save a PDF or Markdown export.')
      if (format === 'pdf') {
        await document.fonts.ready
        for (const image of paper.current?.querySelectorAll('img') ?? []) await image.decode()
      }
      const result = await window.folioDesktop.exportPage({ ...markdownExport(page), format })
      setMessage(result.canceled ? 'Export canceled. Your page is unchanged.' : `Saved to ${result.path}`)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setBusy(false)
    }
  }
  /** Save all pages and folder relationships, including editable graphs. */
  async function saveBackup() {
    setBusy(true)
    try {
      if (!window.folioDesktop) throw new Error('Open Folio desktop to save a backup.')
      const result = await window.folioDesktop.backupRoots()
      setMessage(result.canceled ? 'Backup canceled.' : `Saved to ${result.path}`)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setBusy(false)
    }
  }
  /** Save the rendered page for printing or sharing. */
  function savePdf() {
    void save('pdf')
  }
  /** Save editable notation and graph image attachments. */
  function saveMarkdown() {
    void save('md')
  }
  return (
    <>
      {createPortal(
        <article className="folio-print-document" ref={paper} aria-hidden="true">
          <h1>{page.title || 'Untitled'}</h1>
          {page.cells.map(renderCell)}
        </article>,
        document.body,
      )}
      <Dialog.Root open onOpenChange={close}>
        <Dialog.Portal>
          <Dialog.Backdrop className="focus-cell-backdrop" />
          <Dialog.Popup className="focus-cell-dialog folder-dialog">
            <Dialog.Title className="focus-cell-title">Export {page.title || 'Untitled'}</Dialog.Title>
            <Dialog.Description>PDF preserves the rendered page. Markdown keeps editable text and math, with graph images in a companion folder.</Dialog.Description>
            <div className="folder-dialog-actions">
              <Button onClick={savePdf} disabled={busy}>
                Save PDF
              </Button>
              <Button onClick={saveMarkdown} disabled={busy}>
                Save Markdown
              </Button>
              <Button onClick={onClose} disabled={busy} variant="quiet">
                Close
              </Button>
            </div>
            <Button onClick={saveBackup} disabled={busy} variant="quiet">
              Back up all Roots…
            </Button>
            <p role="status">{busy ? 'Preparing export…' : message}</p>
          </Dialog.Popup>
        </Dialog.Portal>
      </Dialog.Root>
    </>
  )
}
