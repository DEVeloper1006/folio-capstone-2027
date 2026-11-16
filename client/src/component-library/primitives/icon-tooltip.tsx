/**
 * Pair an icon control with a hover and focus tooltip showing its label and optional keyboard shortcut.
 *
 * @file
 */

import type { ReactElement } from 'react'
import { Tooltip } from '@base-ui/react/tooltip'

/** Describe the accessible trigger element, visible tooltip text, and optional shortcut badge. `side` chooses which edge of the trigger the label opens from. */
interface IconTooltipProps {
  label: string
  shortcut?: string
  side?: 'top' | 'right' | 'bottom' | 'left'
  sideOffset?: number
  children: ReactElement
}

/** Wrap an interactive element in a Base UI tooltip so icon-only controls explain what they do without cluttering the toolbar. */
export function IconTooltip({ label, shortcut, side = 'top', sideOffset = 6, children }: IconTooltipProps) {
  return (
    <Tooltip.Root>
      <Tooltip.Trigger render={children} />
      <Tooltip.Portal>
        <Tooltip.Positioner side={side} sideOffset={sideOffset}>
          <Tooltip.Popup className="primitive-tooltip">
            <span>{label}</span>
            {shortcut === undefined ? null : <span className="primitive-kbd">{shortcut}</span>}
          </Tooltip.Popup>
        </Tooltip.Positioner>
      </Tooltip.Portal>
    </Tooltip.Root>
  )
}
