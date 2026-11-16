/**
 * Format a key combination as the label shown in the shortcut table. Contains the keycap marks and the join order the cursor commands match against.
 *
 * @file
 */

/** Accept the key fields needed to build a shortcut label, without the rest of a browser event. */
export type ShortcutKeyInput = Pick<KeyboardEvent, 'key' | 'altKey' | 'ctrlKey' | 'metaKey' | 'shiftKey'>

const shortcutModifiers = new Set(['⌘', '⌃', '⌥', '⇧'])

/** Turn one key into the short mark shown on a keycap. */
export function formatShortcutKey(key: string) {
  if (key === 'ArrowUp') return '↑'
  if (key === 'ArrowDown') return '↓'
  if (key === 'ArrowLeft') return '←'
  if (key === 'ArrowRight') return '→'
  if (key === 'Enter') return '↩'
  if (key === 'Escape') return 'Esc'
  if (key === 'Backspace') return '⌫'
  if (key === ' ') return 'Space'
  if (key.length === 1) return key.toUpperCase()
  return key
}

/** Join the held modifiers and the key into one shortcut label, in menu order. */
export function formatShortcut(event: ShortcutKeyInput) {
  const parts: string[] = []
  if (event.metaKey) parts.push('⌘')
  if (event.ctrlKey) parts.push('⌃')
  if (event.altKey) parts.push('⌥')
  if (event.shiftKey) parts.push('⇧')
  parts.push(formatShortcutKey(event.key))
  return parts.join('')
}

/** Split a shortcut label into the keycap marks to show, keeping modifiers separate from the final key. */
export function shortcutKeys(shortcut: string) {
  const keys: string[] = []
  let index = 0
  while (index < shortcut.length && shortcutModifiers.has(shortcut[index])) {
    keys.push(shortcut[index])
    index += 1
  }
  const remainder = shortcut.slice(index)
  if (remainder) keys.push(remainder)
  return keys
}
