/**
 * Present a notebook block with a right-side drag handle, keyboard actions, nested content, and drop indicators. Delegate all structural changes to the page's shared subtree operations.
 *
 * @file
 */
import { useRef, useState } from 'react'
import type { DragEvent, KeyboardEvent, ReactNode } from 'react'
import { Menu } from '@base-ui/react/menu'
import { GripVertical, MoreHorizontal } from 'lucide-react'
import { blockDestination } from './notebook-blocks'
import type { BlockAction, BlockPlacement, BlockSlot } from './notebook-blocks'
import './notebook-blocks.css'

/** Offer mouse and keyboard routes to the same move, nesting, and deletion operations. */
export function NotebookBlockView({
  cellId,
  index,
  cells,
  descendantCount,
  content,
  children,
  draggedId,
  blocked,
  onDrag,
  onMove,
  onAction,
}: {
  cellId: string
  index: number
  cells: readonly BlockSlot[]
  descendantCount: number
  content: ReactNode
  children: ReactNode
  draggedId: string | null
  blocked: boolean
  onDrag: (id: string | null) => void
  onMove: (id: string, targetId: string, placement: BlockPlacement) => void
  onAction: (id: string, action: BlockAction) => void
}) {
  const row = useRef<HTMLDivElement>(null)
  const [placement, setPlacement] = useState<BlockPlacement | null>(null)
  /** Give only the handle native drag behavior; text selection and graph interactions stay unchanged. */
  function startDrag(event: DragEvent<HTMLButtonElement>) {
    event.dataTransfer.setData('application/x-folio-block', cellId)
    event.dataTransfer.effectAllowed = 'move'
    if (row.current) event.dataTransfer.setDragImage(row.current, row.current.clientWidth - 24, 16)
    onDrag(cellId)
  }
  /** Clear the active drag after a drop or Escape. */
  function endDrag() {
    onDrag(null)
    setPlacement(null)
  }
  /** Use edges for sibling placement and the center for nesting, showing the choice before drop. */
  function dropPlacement(event: DragEvent<HTMLDivElement>): BlockPlacement {
    const bounds = row.current?.getBoundingClientRect() ?? event.currentTarget.getBoundingClientRect()
    const offset = event.clientY - bounds.top
    const edge = Math.min(32, bounds.height / 4)
    return offset < edge ? 'before' : offset > bounds.height - edge ? 'after' : 'inside'
  }
  /** Accept only a live notebook drag and refuse its own subtree as a destination. */
  function dragOver(event: DragEvent<HTMLDivElement>) {
    if (!draggedId) return
    event.stopPropagation()
    event.preventDefault()
    if (blocked) {
      event.dataTransfer.dropEffect = 'none'
      setPlacement(null)
      return
    }
    event.dataTransfer.dropEffect = 'move'
    setPlacement(dropPlacement(event))
  }
  /** Remove the indicator only when leaving this block rather than entering one of its controls. */
  function dragLeave(event: DragEvent<HTMLDivElement>) {
    if (!(event.relatedTarget instanceof Node) || !event.currentTarget.contains(event.relatedTarget)) setPlacement(null)
  }
  /** Commit the exact indicated placement through the current page writer. */
  function drop(event: DragEvent<HTMLDivElement>) {
    if (!draggedId) return
    event.preventDefault()
    event.stopPropagation()
    if (!blocked && event.dataTransfer.getData('application/x-folio-block') === draggedId) onMove(draggedId, cellId, dropPlacement(event))
    endDrag()
  }
  /** Allow moving and nesting without a pointer while the handle owns focus. */
  function handleKey(event: KeyboardEvent<HTMLButtonElement>) {
    const action = event.key === 'ArrowUp' ? 'up' : event.key === 'ArrowDown' ? 'down' : event.key === 'ArrowRight' ? 'nest' : event.key === 'ArrowLeft' ? 'unnest' : event.key === 'Delete' || event.key === 'Backspace' ? 'delete' : null
    if (!action) return
    event.preventDefault()
    event.stopPropagation()
    onAction(cellId, action)
  }
  /** Render one discoverable action with unavailable destinations disabled. */
  function actionItem(action: BlockAction, label: string) {
    /** Dispatch this item against its own stable block id. */
    function run() {
      onAction(cellId, action)
    }
    return (
      <Menu.Item key={action} className={`primitive-item${action === 'delete' ? ' primitive-item-danger' : ''}`} disabled={action !== 'delete' && !blockDestination(cells, cellId, action)} onClick={run}>
        {label}
      </Menu.Item>
    )
  }
  const indicator = draggedId && !blocked ? placement : null
  return (
    <div className="notebook-block" data-block-id={cellId} data-drop={indicator ?? undefined} data-dragging={draggedId === cellId || undefined} onDragOver={dragOver} onDragLeave={dragLeave} onDrop={drop}>
      {indicator && <span className="block-drop-label">{indicator === 'inside' ? 'Nest inside this block' : indicator === 'before' ? 'Move before this block' : 'Move after this block'}</span>}
      <div className="notebook-block-row" ref={row}>
        {content}
        <div className="notebook-block-tools">
          <button type="button" className="block-drag-handle" draggable onDragStart={startDrag} onDragEnd={endDrag} onKeyDown={handleKey} aria-label={`Drag block ${index + 1}`} title="Drag to move. Use arrow keys to move or nest.">
            <GripVertical size={16} aria-hidden="true" />
          </button>
          <Menu.Root>
            <Menu.Trigger className="block-menu-trigger" aria-label={`Block ${index + 1} actions`} title="Block actions">
              <MoreHorizontal size={16} aria-hidden="true" />
            </Menu.Trigger>
            <Menu.Portal>
              <Menu.Positioner sideOffset={6} align="end">
                <Menu.Popup className="primitive-popup">
                  {actionItem('up', 'Move up')}
                  {actionItem('down', 'Move down')}
                  {actionItem('nest', 'Nest under previous block')}
                  {actionItem('unnest', 'Move out one level')}
                  <Menu.Separator className="primitive-separator" />
                  {actionItem('delete', descendantCount ? `Delete block and ${descendantCount} nested ${descendantCount === 1 ? 'block' : 'blocks'}` : 'Delete block')}
                </Menu.Popup>
              </Menu.Positioner>
            </Menu.Portal>
          </Menu.Root>
        </div>
      </div>
      {descendantCount > 0 && (
        <div className="notebook-block-children" role="group" aria-label={`Nested blocks in block ${index + 1}`}>
          {children}
        </div>
      )}
    </div>
  )
}
