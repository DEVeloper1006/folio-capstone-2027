/**
 * Translate keyboard combinations into named navigation actions. Contains action and selection types plus the keyboard decoder.
 *
 * @file
 */

/** Name a movement or selection operation independently of the keyboard shortcut that triggers it. */
export type NavigationActionName = 'moveLeft' | 'moveRight' | 'moveUp' | 'moveDown' | 'blockStart' | 'blockEnd' | 'rootStart' | 'rootEnd' | 'selectUp' | 'selectDown' | 'tabForward' | 'tabBackward' | 'skipBackward' | 'skipForward' | 'leave' | 'enter' | 'grow' | 'shrink'

/** Pair a decoded operation with whether it should extend the selection. Individual rules decide how selection extension crosses structural boundaries. */
export interface NavigationAction {
  name: NavigationActionName
  extend: boolean
}

/** Represent a selection using MathLive cursor offsets: anchor stays fixed while focus moves. Equal endpoints form a cursor; focus before anchor represents a backward selection. */
export interface CursorSelection {
  anchor: number
  focus: number
}

/** Limit keyboard decoding to the key, modifier flags, and composition status it needs, without requiring access to a browser event's methods. */
type NavigationKeyInput = Pick<KeyboardEvent, 'key' | 'altKey' | 'ctrlKey' | 'metaKey' | 'shiftKey' | 'isComposing'>

/** Decode keyboard movement, block selection, Tab, and Home/End. Preserve composition and unrelated platform shortcuts for MathLive or the browser. */
export function getNavigationAction(event: NavigationKeyInput): NavigationAction | undefined {
  if (event.isComposing || event.metaKey) return undefined
  if (event.ctrlKey) {
    if (!event.altKey && (event.key === 'Home' || event.key === 'End')) return { name: event.key === 'Home' ? 'rootStart' : 'rootEnd', extend: event.shiftKey }
    return undefined
  }

  if (!event.altKey) {
    if (event.key === 'ArrowLeft') return { name: 'moveLeft', extend: event.shiftKey }
    if (event.key === 'ArrowRight') return { name: 'moveRight', extend: event.shiftKey }
    if (event.key === 'ArrowUp') return { name: event.shiftKey ? 'selectUp' : 'moveUp', extend: event.shiftKey }
    if (event.key === 'ArrowDown') return { name: event.shiftKey ? 'selectDown' : 'moveDown', extend: event.shiftKey }
    if (event.key === 'Home' || event.key === 'End') return { name: event.key === 'Home' ? 'blockStart' : 'blockEnd', extend: event.shiftKey }
    if (event.key === 'Tab' || event.key === 'Escape') return { name: event.shiftKey ? 'tabBackward' : 'tabForward', extend: false }
    return undefined
  }

  switch (event.key) {
    case 'ArrowLeft':
      return { name: 'skipBackward', extend: event.shiftKey }
    case 'ArrowRight':
      return { name: 'skipForward', extend: event.shiftKey }
    case 'ArrowUp':
      return { name: event.shiftKey ? 'grow' : 'leave', extend: false }
    case 'ArrowDown':
      return { name: event.shiftKey ? 'shrink' : 'enter', extend: false }
    default:
      return undefined
  }
}
