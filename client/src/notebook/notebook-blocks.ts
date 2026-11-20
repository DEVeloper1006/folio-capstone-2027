/**
 * Move, nest, delete, and restore notebook subtrees in the existing ordered cell list. Depth uses preorder: children follow their parent until a block at the same or a shallower level. Preserve identities and editor payloads through every operation.
 *
 * @file
 */
import type { NotebookCell } from './notebook-cells'
import type { Page } from './page'

export type BlockSlot = Pick<NotebookCell, 'cellId' | 'kind' | 'depth'>
export type BlockPlacement = 'before' | 'inside' | 'after'
export type BlockAction = 'up' | 'down' | 'nest' | 'unnest' | 'delete'

/** Read old flat cells as top-level blocks without migrating their records. */
export function blockDepth(cell: Pick<NotebookCell, 'depth'>) {
  return cell.depth ?? 0
}

/** Return the exclusive end of a block and every descendant. */
export function blockEnd(cells: readonly BlockSlot[], index: number) {
  const root = index >= 0 ? cells.at(index) : undefined
  if (!root) return index
  let end = index + 1
  while (end < cells.length && blockDepth(cells[end]) > blockDepth(root)) end++
  return end
}

/** Locate a stable block id without relying on a stale render index. */
export function blockIndex(cells: readonly BlockSlot[], id: string) {
  /** Compare one block's stable identity. */
  function matches(cell: BlockSlot) {
    return cell.cellId === id
  }
  return cells.findIndex(matches)
}

/** Find the nearest preceding ancestor one level above this block. */
export function blockParent(cells: readonly BlockSlot[], index: number) {
  const depth = cells[index] ? blockDepth(cells[index]) : 0
  for (let i = index - 1; i >= 0 && depth > 0; i--) if (blockDepth(cells[i]) < depth) return i
  return -1
}

/** Refuse malformed hierarchy or duplicate ids before changing persisted data. */
function validateBlocks(cells: readonly BlockSlot[]) {
  const ids = new Set<string>()
  let previous = -1
  for (const cell of cells) {
    const depth = blockDepth(cell)
    if (!Number.isInteger(depth) || depth < 0 || depth > previous + 1 || ids.has(cell.cellId)) throw new Error('This page has an invalid block hierarchy. No blocks were changed.')
    ids.add(cell.cellId)
    previous = depth
  }
}

/** Rebase a subtree to a new parent without changing its relative nesting or content. */
function rebaseBlocks(cells: readonly NotebookCell[], depth: number) {
  const offset = depth - blockDepth(cells[0])
  /** Copy only the nesting metadata, preserving graph images, formulas, and prose. */
  function rebase(cell: NotebookCell): NotebookCell {
    return { ...cell, depth: blockDepth(cell) + offset }
  }
  return cells.map(rebase)
}

/** Move a whole subtree before, inside, or after another block. Reject placing a block inside itself or its descendants. */
export function moveBlock(page: Page, id: string, targetId: string, placement: BlockPlacement): Page {
  const cells = page.cells
  validateBlocks(cells)
  const start = blockIndex(cells, id)
  const target = blockIndex(cells, targetId)
  if (start < 0 || target < 0) return page
  const end = blockEnd(cells, start)
  if (target >= start && target < end) return page
  const insertion = placement === 'before' ? target : blockEnd(cells, target)
  const depth = blockDepth(cells[target]) + (placement === 'inside' ? 1 : 0)
  const moved = rebaseBlocks(cells.slice(start, end), depth)
  const remaining = [...cells.slice(0, start), ...cells.slice(end)]
  remaining.splice(insertion > start ? insertion - (end - start) : insertion, 0, ...moved)
  validateBlocks(remaining)
  return { ...page, cells: remaining }
}

/** Resolve menu actions against siblings and parents, using the same destinations as drag and drop. */
export function blockDestination(cells: readonly BlockSlot[], id: string, action: Exclude<BlockAction, 'delete'>): { targetId: string; placement: BlockPlacement } | undefined {
  const index = blockIndex(cells, id)
  if (index < 0) return
  const depth = blockDepth(cells[index])
  if (action === 'unnest') {
    const parentIndex = blockParent(cells, index)
    return parentIndex >= 0 ? { targetId: cells[parentIndex].cellId, placement: 'after' } : undefined
  }
  if (action === 'down') {
    const next = cells.at(blockEnd(cells, index))
    return next && blockDepth(next) === depth ? { targetId: next.cellId, placement: 'after' } : undefined
  }
  for (let i = index - 1; i >= 0; i--) {
    if (blockDepth(cells[i]) < depth) return
    if (blockDepth(cells[i]) === depth) return { targetId: cells[i].cellId, placement: action === 'nest' ? 'inside' : 'before' }
  }
}

/** Remove a block and its descendants while retaining all of them in the page's saved undo stack. */
export function deleteBlock(page: Page, id: string): Page {
  validateBlocks(page.cells)
  const start = blockIndex(page.cells, id)
  if (start < 0) return page
  const end = blockEnd(page.cells, start)
  const parent = blockParent(page.cells, start)
  const deleted = { cells: page.cells.slice(start, end), nextCellId: page.cells[end]?.cellId, parentCellId: page.cells[parent]?.cellId }
  return { ...page, cells: [...page.cells.slice(0, start), ...page.cells.slice(end)], deletedBlocks: [...(page.deletedBlocks ?? []), deleted] }
}

/** Restore the last deleted subtree before its surviving neighbor, otherwise under its surviving parent or at page end. Keep newer edits intact. */
export function restoreBlock(page: Page): Page {
  validateBlocks(page.cells)
  const deleted = page.deletedBlocks?.at(-1)
  if (!deleted?.cells.length) return page
  const parent = deleted.parentCellId ? blockIndex(page.cells, deleted.parentCellId) : -1
  const next = deleted.nextCellId ? blockIndex(page.cells, deleted.nextCellId) : -1
  const beforeSibling = next >= 0 && blockParent(page.cells, next) === parent
  const insertion = beforeSibling ? next : parent >= 0 ? blockEnd(page.cells, parent) : page.cells.length
  const depth = parent >= 0 ? blockDepth(page.cells[parent]) + 1 : 0
  const cells = [...page.cells]
  cells.splice(insertion, 0, ...rebaseBlocks(deleted.cells, depth))
  validateBlocks(cells)
  return { ...page, cells, deletedBlocks: page.deletedBlocks?.slice(0, -1) }
}
