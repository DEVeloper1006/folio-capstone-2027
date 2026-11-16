/**
 * Open a panel from a button. Contains the trigger, the panel, and dismissal when Escape is pressed or the pointer lands outside.
 *
 * @file
 */

import { useEffect, useId, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Button } from './button.tsx'
import type { ButtonVariant } from './button.tsx'

/** Choose which horizontal edge of the panel lines up with the trigger. End keeps a top-right menu inside the page. */
export type PopoverAlign = 'start' | 'end'

/** Name the popover, choose the trigger's appearance, and supply the panel content. The popover owns whether that panel is open. */
export interface PopoverProps {
  label: string
  trigger: ReactNode
  triggerVariant?: ButtonVariant
  align?: PopoverAlign
  children: ReactNode
}

/** Show the panel under its trigger and close it without changing the panel's contents. Start alignment lines up the panel's left edge; end alignment lines up its right edge. Focus stays where it was, matching the page menu. */
export function Popover({ label, trigger, triggerVariant = 'icon', align = 'start', children }: PopoverProps) {
  const [isOpen, setIsOpen] = useState(false)
  const popoverRef = useRef<HTMLDivElement>(null)
  const panelId = useId()

  /** Close the panel when Escape is pressed or the pointer event starts outside the trigger and panel. */
  function closeOnDismiss(event: PointerEvent | KeyboardEvent) {
    if (event instanceof KeyboardEvent) {
      if (event.key === 'Escape') setIsOpen(false)
      return
    }
    if (!popoverRef.current?.contains(event.target as Node)) setIsOpen(false)
  }

  /** Listen for dismissal while the panel is open, and remove those listeners when it closes or the popover unmounts. */
  function listenForDismiss() {
    if (!isOpen) return undefined
    document.addEventListener('pointerdown', closeOnDismiss)
    document.addEventListener('keydown', closeOnDismiss)
    /** Remove the dismissal listeners installed for the open panel. */
    function removeDismissListeners() {
      document.removeEventListener('pointerdown', closeOnDismiss)
      document.removeEventListener('keydown', closeOnDismiss)
    }
    return removeDismissListeners
  }
  useEffect(listenForDismiss, [isOpen])

  /** Open the panel, or close it when it is already open. */
  function toggleOpen() {
    /** Flip the panel between open and closed. */
    function invertOpen(open: boolean) {
      return !open
    }
    setIsOpen(invertOpen)
  }

  return (
    <div className="ui-popover" ref={popoverRef}>
      <Button variant={triggerVariant} aria-label={label} aria-expanded={isOpen} aria-controls={isOpen ? panelId : undefined} onClick={toggleOpen}>
        {trigger}
      </Button>
      {isOpen ? (
        <div className={`ui-popover-panel ui-popover-panel-${align}`} id={panelId} aria-label={label}>
          {children}
        </div>
      ) : null}
    </div>
  )
}
