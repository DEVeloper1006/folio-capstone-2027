/**
 * Supply the whole current page to math assistance and identify the selected problem. Section boundaries determine subject inheritance, not which page content is sent. Graph expressions are included without image bytes.
 *
 * @file
 */
import { blockDepth, blockIndex, blockParent } from '../notebook/notebook-blocks'
import { cellSource } from '../notebook/notebook-cells'
import type { Page } from '../notebook/page'
import type { MathMode, MathPreferences } from './math-modes'
import { builtinModes } from './math-modes'

/** Locate the current problem's note or top-level subtree and stop at the next section. */
export function mathSection(page: Page, cellId?: string) {
  const selected = cellId ? blockIndex(page.cells, cellId) : 0
  if (selected < 0 || !page.cells.length) return undefined
  let start = selected
  while (blockDepth(page.cells[start]) > 0) start = blockParent(page.cells, start)
  if (page.cells[start].kind !== 'markdown' && !page.cells[start].mathMode) {
    for (let i = start - 1; i >= 0; i--) {
      if (blockDepth(page.cells[i]) !== 0) continue
      start = i
      if (page.cells[i].kind === 'markdown' || page.cells[i].mathMode) break
    }
  }
  const root = page.cells[start]
  /** Label every block and explicitly identify the learner's current problem. */
  function contextualSource(cell: Page['cells'][number], index: number) {
    return `Block ${index + 1}${index === selected ? ' [SELECTED BLOCK]' : ''}${index === start ? ' [CURRENT PROBLEM]' : ''}:\n${source(cell)}`
  }
  const context = `Page: ${page.title}\nCurrent problem starts at block ${start + 1}. Selected block: ${selected + 1}. Use the entire page as context; help with this problem only.\n\n${page.cells.map(contextualSource).join('\n\n')}`
  return { rootId: root.cellId, cellId: page.cells[selected].cellId, start, context, previous: page.cells.slice(start, selected).map(source).join('\n'), modeId: root.mathMode }
}
/** Include graph expressions and math captions, never captured image bytes. */
function source(cell: Page['cells'][number]) {
  if (cell.kind === 'graph') return JSON.stringify({ dimension: cell.graph.dimension, expressions: cell.graph.expressions[cell.graph.dimension], parameters: cell.graph.parameters })
  return (cell.kind === 'math' && cell.caption ? cell.caption + '\n' : '') + cellSource(cell)
}
/** Resolve the mode explicitly assigned to this section, otherwise the configured default. Missing saved modes remain visible as an error. */
export function sectionMode(page: Page, cellId: string | undefined, preferences: MathPreferences): MathMode {
  const id = mathSection(page, cellId)?.modeId ?? preferences.default_mode
  /** Find the exact persisted subject without silently selecting another one. */
  function matches(mode: MathMode) {
    return mode.id === id
  }
  const mode = [...builtinModes, ...preferences.modes].find(matches)
  if (!mode) throw new Error(`Math mode "${id}" is missing. Choose a mode for this section.`)
  return mode
}
