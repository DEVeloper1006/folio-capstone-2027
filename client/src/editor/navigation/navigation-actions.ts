/**
 * Translate keyboard combinations into named navigation actions. Contains action and selection types plus the keyboard decoder. The decoder reads the cursor command catalog, so a shortcut recorded in settings replaces the default key.
 *
 * @file
 */

import { cursorCommandBindings } from '#/editor/commands/cursor-commands.ts'
import type { CursorCommandBinding } from '#/editor/commands/cursor-commands.ts'
import { formatShortcut } from '#/editor/commands/shortcut-label.ts'
import type { ShortcutOverrides } from '../commands/shortcut-overrides.ts'
import { shortcutLabel } from '#/editor/commands/shortcut-overrides.ts'

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

/** Resolve a key through the cursor commands. The first command whose current shortcut label matches the key runs. Composition and every unmatched key stay with MathLive or the browser. */
export function getNavigationAction(event: NavigationKeyInput, overrides?: ShortcutOverrides): NavigationAction | undefined {
  if (event.isComposing) return undefined
  const shortcut = formatShortcut(event)
  /** Keep the cursor command whose recorded or default shortcut is this key. */
  function matchesShortcut(binding: CursorCommandBinding) {
    return shortcutLabel(binding.id, binding.shortcut, overrides) === shortcut
  }
  const binding = cursorCommandBindings.find(matchesShortcut)
  if (!binding) return undefined
  return { name: binding.name, extend: binding.extend }
}
