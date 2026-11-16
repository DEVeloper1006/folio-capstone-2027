/**
 * List the formula cursor movements as editor commands. Contains each movement's stable id, the keybinding the formula uses, and the navigation action that key runs. The movement rules stay in the navigation module.
 *
 * @file
 */

import type { NavigationActionName } from '#/editor/navigation/navigation-actions.ts'

/** Pair one cursor command with the navigation action its keybinding runs. `extend` asks the rule to grow the selection instead of moving the caret. */
export interface CursorCommandBinding {
  id: string
  label: string
  keywords: readonly string[]
  when: string
  shortcut: string
  name: NavigationActionName
  extend: boolean
}

const cursorWhen = 'mathFocus && !latexMode'

/** Build one cursor command. The id is the stable path under `workspace.currentPage.cell.cursor`. */
function cursorCommand(id: string, label: string, shortcut: string, name: NavigationActionName, extend: boolean, keywords: readonly string[]): CursorCommandBinding {
  return { id: `workspace.currentPage.cell.cursor.${id}`, label, keywords, when: cursorWhen, shortcut, name, extend }
}

/** Cursor commands in table order. Each shortcut is the label `formatShortcut` produces for that key combination. */
export const cursorCommandBindings: readonly CursorCommandBinding[] = [
  cursorCommand('moveLeft', 'Move left', '←', 'moveLeft', false, ['cursor', 'left', 'arrow']),
  cursorCommand('extendLeft', 'Extend selection left', '⇧←', 'moveLeft', true, ['cursor', 'left', 'select']),
  cursorCommand('moveRight', 'Move right', '→', 'moveRight', false, ['cursor', 'right', 'arrow']),
  cursorCommand('extendRight', 'Extend selection right', '⇧→', 'moveRight', true, ['cursor', 'right', 'select']),
  cursorCommand('moveUp', 'Move up', '↑', 'moveUp', false, ['cursor', 'up', 'arrow']),
  cursorCommand('selectUp', 'Select up', '⇧↑', 'selectUp', true, ['cursor', 'up', 'select']),
  cursorCommand('moveDown', 'Move down', '↓', 'moveDown', false, ['cursor', 'down', 'arrow']),
  cursorCommand('selectDown', 'Select down', '⇧↓', 'selectDown', true, ['cursor', 'down', 'select']),
  cursorCommand('skipBackward', 'Skip to previous term', '⌥←', 'skipBackward', false, ['cursor', 'word', 'term', 'previous']),
  cursorCommand('extendSkipBackward', 'Extend selection to previous term', '⌥⇧←', 'skipBackward', true, ['cursor', 'word', 'term', 'select']),
  cursorCommand('skipForward', 'Skip to next term', '⌥→', 'skipForward', false, ['cursor', 'word', 'term', 'next']),
  cursorCommand('extendSkipForward', 'Extend selection to next term', '⌥⇧→', 'skipForward', true, ['cursor', 'word', 'term', 'select']),
  cursorCommand('blockStart', 'Go to block start', 'Home', 'blockStart', false, ['cursor', 'start', 'block', 'home']),
  cursorCommand('extendBlockStart', 'Extend selection to block start', '⇧Home', 'blockStart', true, ['cursor', 'start', 'block', 'select']),
  cursorCommand('blockEnd', 'Go to block end', 'End', 'blockEnd', false, ['cursor', 'end', 'block']),
  cursorCommand('extendBlockEnd', 'Extend selection to block end', '⇧End', 'blockEnd', true, ['cursor', 'end', 'block', 'select']),
  cursorCommand('rootStart', 'Go to formula start', '⌃Home', 'rootStart', false, ['cursor', 'start', 'formula', 'home']),
  cursorCommand('extendRootStart', 'Extend selection to formula start', '⌃⇧Home', 'rootStart', true, ['cursor', 'start', 'formula', 'select']),
  cursorCommand('rootEnd', 'Go to formula end', '⌃End', 'rootEnd', false, ['cursor', 'end', 'formula']),
  cursorCommand('extendRootEnd', 'Extend selection to formula end', '⌃⇧End', 'rootEnd', true, ['cursor', 'end', 'formula', 'select']),
  cursorCommand('leave', 'Leave structure', '⌥↑', 'leave', false, ['cursor', 'exit', 'structure']),
  cursorCommand('grow', 'Grow selection', '⌥⇧↑', 'grow', false, ['cursor', 'selection', 'expand']),
  cursorCommand('enter', 'Enter structure', '⌥↓', 'enter', false, ['cursor', 'enter', 'structure']),
  cursorCommand('shrink', 'Shrink selection', '⌥⇧↓', 'shrink', false, ['cursor', 'selection', 'reduce']),
  cursorCommand('tabForward', 'Next placeholder', 'Tab', 'tabForward', false, ['cursor', 'placeholder', 'tab']),
  cursorCommand('tabBackward', 'Previous placeholder', '⇧Tab', 'tabBackward', false, ['cursor', 'placeholder', 'tab']),
  cursorCommand('tabBackwardEscape', 'Previous placeholder', '⇧Esc', 'tabBackward', false, ['cursor', 'placeholder', 'escape']),
]
