/**
 * Check the command catalog and its local search. Contains assertions for empty queries, exact aliases, and parent ranking.
 *
 * @file
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'
import { expressionCommands } from './expression-commands.ts'
import { searchExpressionCommands } from './expression-command-search.ts'

/** Read one catalog command's ID. */
function commandIdFromGroup(command: { id: string }) {
  return command.id
}

/** Read one result's command ID. */
function commandId(match: { command: { id: string } }) {
  return match.command.id
}

/** Read the command IDs in result order. */
function commandIds(matches: readonly { command: { id: string } }[]) {
  return matches.map(commandId)
}

test('an empty query lists only the top-level commands', async () => {
  const matches = await searchExpressionCommands({ query: '  ' })
  assert.deepEqual(commandIds(matches), expressionCommands.map(commandIdFromGroup))
})

test('a variant alias selects that variant and keeps its parent', async () => {
  const matches = await searchExpressionCommands({ query: 'contour integral' })
  assert.equal(matches[0]?.command.id, 'contour-integral')
  assert.equal(matches[0]?.parent?.id, 'integral')
})

test('int ranks the integral parent ahead of its variants', async () => {
  const matches = await searchExpressionCommands({ query: 'int' })
  assert.equal(matches[0]?.command.id, 'integral')
})
