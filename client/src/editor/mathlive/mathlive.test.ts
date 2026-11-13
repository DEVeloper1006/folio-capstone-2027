/**
 * Check MathLive field configuration that does not need a browser. Contains the virtual-keyboard binding filter.
 *
 * @file
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'
import { withoutVirtualKeyboardToggle } from './use-mathlive.ts'
import type { MathfieldElement } from 'mathlive'

/** Build the binding records the filter reads. The remaining MathLive binding fields are unused. */
function binding(command: string): MathfieldElement['keybindings'][number] {
  return { key: 'command', command } as MathfieldElement['keybindings'][number]
}

test('the virtual-keyboard toggle is removed and other bindings stay', () => {
  const keybindings = withoutVirtualKeyboardToggle([binding('moveToNextChar'), binding('toggleVirtualKeyboard'), binding('moveToPreviousChar')])
  /** Read the MathLive command name kept on a binding. */
  function commandName(keybinding: MathfieldElement['keybindings'][number]) {
    return keybinding.command
  }
  assert.deepEqual(keybindings.map(commandName), ['moveToNextChar', 'moveToPreviousChar'])
})
