/**
 * Define and validate portable notebook snapshots at the desktop boundary. Markdown holds visible text; the snapshot retains identities, nested blocks, graph views, and deletion history.
 *
 * @file
 */
import type { NotebookState } from '../state/global-states'
import type { Page } from './page'
import type { NotebookCell } from './notebook-cells'
import type { GraphDocument, GraphSnapshot } from '../graph/graph-model'

export interface NotebookSnapshot {
  version: 1
  list: NotebookState
  pages: Page[]
}
/** Require an object without relying on a type cast. */
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid notebook object.')
  return Object.fromEntries(Object.entries(value))
}
/** Require text where the renderer expects text. */
function text(value: unknown): asserts value is string {
  if (typeof value !== 'string') throw new Error('Invalid notebook text.')
}
/** Keep stable identities safe in Markdown markers and attachment filenames. */
function identity(value: unknown): asserts value is string {
  text(value)
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(value)) throw new Error('Invalid notebook identity.')
}
/** Require a bounded integer used for identity counts, nesting, or dimensions. */
function integer(value: unknown, min: number, max: number): asserts value is number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) throw new Error('Invalid notebook number.')
}
/** Check editable graph structure while retaining the user's exact equations and camera data. */
function graph(value: unknown): asserts value is GraphDocument {
  const g = record(value)
  if (g.dimension !== '2d' && g.dimension !== '3d') throw new Error('Invalid graph dimension.')
  const expressions = record(g.expressions)
  for (const dimension of ['2d', '3d']) {
    const rows = expressions[dimension]
    if (!Array.isArray(rows) || rows.length > 1000) throw new Error('Invalid graph expressions.')
    for (const row of rows) {
      const r = record(row)
      text(r.id)
      text(r.source)
      if (typeof r.visible !== 'boolean') throw new Error('Invalid graph visibility.')
    }
  }
  const domain = record(g.domain)
  for (const key of ['xmin', 'xmax', 'ymin', 'ymax']) if (typeof domain[key] !== 'number' || !Number.isFinite(domain[key])) throw new Error('Invalid graph bounds.')
  for (const parameter of Object.values(record(g.parameters))) {
    const p = record(parameter)
    for (const key of ['value', 'min', 'max', 'step']) if (typeof p[key] !== 'number' || !Number.isFinite(p[key])) throw new Error('Invalid graph parameter.')
  }
}
/** Validate the captured image and JSON layout without executing content. */
function snapshot(value: unknown): asserts value is GraphSnapshot {
  const s = record(value)
  text(s.image)
  if (!s.image.startsWith('data:image/png;base64,')) throw new Error('Graph snapshots must be PNG images.')
  integer(s.width, 1, 32768)
  integer(s.height, 1, 32768)
  const layout = record(s.layout)
  for (const key of ['xaxis', 'yaxis', 'scene']) if (layout[key] !== undefined) record(layout[key])
}
/** Validate every cell before importing it into the live editor. */
function cells(value: unknown, hierarchy = true): asserts value is NotebookCell[] {
  if (!Array.isArray(value) || value.length > 50000) throw new Error('Invalid notebook cells.')
  const ids = new Set<string>()
  let previous = -1
  for (const item of value) {
    const cell = record(item)
    identity(cell.cellId)
    if (!cell.cellId || ids.has(cell.cellId)) throw new Error('Duplicate or empty cell identity.')
    ids.add(cell.cellId)
    const depth = cell.depth ?? 0
    integer(depth, 0, 100)
    if (hierarchy && depth > previous + 1) throw new Error('Invalid block nesting.')
    previous = depth
    if (cell.mathMode !== undefined) text(cell.mathMode)
    if (cell.kind === 'markdown') text(cell.markdown)
    else if (cell.kind === 'math') {
      text(cell.latex)
      if (cell.caption !== undefined) text(cell.caption)
    } else if (cell.kind === 'graph') {
      graph(cell.graph)
      snapshot(cell.snapshot)
    } else throw new Error('Unknown notebook cell kind.')
  }
}
/** Reject malformed imported pages while preserving optional, older document fields. */
function page(value: unknown): asserts value is Page {
  const p = record(value)
  identity(p.pageId)
  text(p.title)
  cells(p.cells)
  const metadata = record(p.pageMetadata)
  if (!['narrow', 'full'].includes(String(metadata.width)) || !['source', 'rich'].includes(String(metadata.editorMode))) throw new Error('Invalid page display settings.')
  integer(metadata.cellSpacingPx, 0, 1000)
  if (p.graph !== undefined) graph(p.graph)
  if (p.deletedBlocks !== undefined) {
    if (!Array.isArray(p.deletedBlocks)) throw new Error('Invalid deleted blocks.')
    for (const item of p.deletedBlocks) {
      const deleted = record(item)
      cells(deleted.cells, false)
      if (deleted.nextCellId !== undefined) text(deleted.nextCellId)
      if (deleted.parentCellId !== undefined) text(deleted.parentCellId)
    }
  }
}
/** Validate identities and parent chains before storage, migration, or restore. */
export function parseNotebook(source: string): NotebookSnapshot {
  if (source.length > 128 * 1024 * 1024) throw new Error('Notebook exceeds the 128 MB import limit.')
  const value = record(JSON.parse(source))
  if (value.version !== 1 || !Array.isArray(value.pages) || value.pages.length < 1 || value.pages.length > 10000) throw new Error('Unsupported or empty Folio backup.')
  const pages: Page[] = []
  const ids = new Set<string>()
  for (const item of value.pages) {
    page(item)
    if (!item.pageId || ids.has(item.pageId)) throw new Error('Duplicate page identity.')
    ids.add(item.pageId)
    pages.push(item)
  }
  const list = record(value.list)
  text(list.openPageId)
  if (!ids.has(list.openPageId) || !Array.isArray(list.pages) || list.pages.length !== pages.length) throw new Error('Invalid notebook page list.')
  const folders: NonNullable<NotebookState['folders']>[number][] = []
  const folderIds = new Set<string>()
  if (list.folders !== undefined && !Array.isArray(list.folders)) throw new Error('Invalid notebook folders.')
  for (const item of list.folders ?? []) {
    const f = record(item)
    identity(f.folderId)
    text(f.title)
    if (!f.folderId || !f.title.trim() || folderIds.has(f.folderId)) throw new Error('Duplicate or empty folder identity.')
    if (f.parentId !== undefined) text(f.parentId)
    folderIds.add(f.folderId)
    folders.push({ folderId: f.folderId, title: f.title, parentId: f.parentId })
  }
  for (const folder of folders) {
    const seen = new Set<string>([folder.folderId])
    let parent = folder.parentId
    while (parent) {
      if (seen.has(parent) || !folderIds.has(parent)) throw new Error('Invalid folder parent or cycle.')
      seen.add(parent)
      /** Resolve a validated ancestor. */
      function ancestor(item: typeof folder) {
        return item.folderId === parent
      }
      parent = folders.find(ancestor)?.parentId
    }
  }
  const entries: NotebookState['pages'][number][] = []
  const listed = new Set<string>()
  for (const item of list.pages) {
    const entry = record(item)
    text(entry.pageId)
    text(entry.title)
    if (!ids.has(entry.pageId) || listed.has(entry.pageId)) throw new Error('Invalid listed page.')
    listed.add(entry.pageId)
    if (entry.folderId !== undefined) {
      text(entry.folderId)
      if (!folderIds.has(entry.folderId)) throw new Error('Missing page folder.')
    }
    entries.push({ pageId: entry.pageId, title: entry.title, folderId: entry.folderId })
  }
  return { version: 1, list: { pages: entries, folders, openPageId: list.openPageId }, pages }
}
