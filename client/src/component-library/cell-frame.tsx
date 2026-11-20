/**
 * Draw notebook rows and their gutter controls using the same states in the notebook and component gallery.
 *
 * @file
 */
import type { ComponentProps, ReactNode } from 'react'
import { IconTooltip } from './primitives/icon-tooltip'

export type CellFrameState = 'unselected' | 'selected' | 'focused' | 'editing' | 'empty' | 'computing' | 'error'

/** Render a state-colored row with room for either cell editor and an optional labeled gutter action. */
export function CellFrame({ state, icon, label, onSelect, children, ...props }: ComponentProps<'div'> & { state: CellFrameState; icon?: ReactNode; label?: string; onSelect?: () => void }) {
  return (
    <div {...props} className={`notebook-live-cell notebook-state-${state}`} data-cell-state={state}>
      {label && (
        <IconTooltip label={label}>
          <button type="button" className="notebook-cell-gutter" aria-label={label} onClick={onSelect}>
            {icon}
          </button>
        </IconTooltip>
      )}
      <div className="notebook-live-cell-body">{children}</div>
    </div>
  )
}
