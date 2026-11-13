/**
 * Describe the existing navigation-transition regression checks. Contains nested-fraction fixtures and assertions for rule dispatch, selection anchors, growth history, and keyboard decoding.
 *
 * @file
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'
import { getNavigationAction } from './navigation-actions.ts'
import { fractionEndUpRule } from './navigation-rules.ts'
import { createNavigationState, applyNavigationAction } from './navigation-transition.ts'
import { buildStructure } from './structure.ts'
import type { NavigationContext } from './navigation-transition.ts'

const entries: Array<[number, string]> = [
  [0, ''],
  [1, ''],
  [2, ''],
  [2, 'a'],
  [2, '-'],
  [2, 'b'],
  [2, ''],
  [2, 'c'],
  [1, String.raw`\frac{a-b}{c}`],
  [1, ''],
  [2, ''],
  [2, 'd'],
  [2, '+'],
  [2, 'b'],
  [2, ''],
  [2, 'e'],
  [2, '+'],
  [2, 'g'],
  [1, String.raw`\frac{d+b}{e+g}`],
  [0, String.raw`\frac{\frac{a-b}{c}}{\frac{d+b}{e+g}}`],
]

/** Convert the recorded nested-fraction metadata into the public snapshot shape used by the navigation model. */
const snapshotFromEntry = ([depth, latex]: [number, string]) => ({
  depth,
  latex,
})

const structure = buildStructure(entries.map(snapshotFromEntry))
const x = new Map([
  [2, 45],
  [3, 55],
  [4, 71],
  [5, 82],
  [8, 85],
])
const context: NavigationContext = {
  structure,

  /** Return the recorded horizontal coordinate for a fixture cursor offset. */
  xAt: (position) => x.get(position),
}

/** Create a collapsed selection at the requested fixture offset with empty growth history. */
const caret = (position: number) => createNavigationState({ anchor: position, focus: position })

/** Verify that up after the inner fraction enters a-b instead of remaining at the boundary. */
const verifyInnerFractionEntry = () => {
  const result = applyNavigationAction(caret(8), { name: 'moveUp', extend: false }, context)
  assert.equal(result.handled, true)
  assert.deepEqual(result.state.selection, { anchor: 5, focus: 5 })
}

test('up after the inner fraction enters a-b instead of remaining at the boundary', verifyInnerFractionEntry)

/** Verify that the same fraction-end rule works recursively at the outer fraction. */
const verifyOuterFractionEntry = () => {
  const result = applyNavigationAction(caret(19), { name: 'moveUp', extend: false }, context)
  assert.equal(result.handled, true)
  assert.equal(result.state.selection.focus, 8)
}

test('the same fraction-end rule works recursively at the outer fraction', verifyOuterFractionEntry)

/** Verify that shift-up uses the same rule and preserves the selection anchor. */
const verifyShiftAnchor = () => {
  const state = createNavigationState({ anchor: 1, focus: 8 })
  const result = applyNavigationAction(state, { name: 'moveUp', extend: true }, context)
  assert.deepEqual(result.state.selection, { anchor: 1, focus: 5 })
}

test('shift-up uses the same rule and preserves the selection anchor', verifyShiftAnchor)

/** Verify that fraction entry chooses the closest horizontal position within the numerator. */
const verifyHorizontalAlignment = () => {
  const result = applyNavigationAction(
    caret(8),
    { name: 'moveUp', extend: false },
    {
      ...context,

      /** Place the fraction boundary near the first numerator symbol to exercise horizontal alignment. */
      xAt: (position) => (position === 8 ? 56 : x.get(position)),
    },
  )
  assert.equal(result.state.selection.focus, 3)
}

test('fraction entry chooses the closest horizontal position within the numerator', verifyHorizontalAlignment)

/** Verify that missing geometry still enters the numerator. */
const verifyMissingGeometry = () => {
  const result = applyNavigationAction(
    caret(8),
    { name: 'moveUp', extend: false },
    {
      ...context,

      /** Simulate unavailable cursor geometry so the rule uses its structural fallback. */
      xAt: () => undefined,
    },
  )
  assert.equal(result.state.selection.focus, 5)
}

test('missing geometry still enters the numerator', verifyMissingGeometry)

/** Verify that unmatched vertical movements fall back to MathLive. */
const verifyNativeFallback = () => {
  for (const position of [3, 5, 7]) {
    assert.equal(applyNavigationAction(caret(position), { name: 'moveUp', extend: false }, context).handled, false)
  }
  assert.equal(applyNavigationAction(caret(8), { name: 'moveDown', extend: false }, context).handled, false)
}

test('unmatched vertical movements fall back to MathLive', verifyNativeFallback)

/** Verify that the registry accepts another node rule without changing the key handler. */
const verifyRuleRegistration = () => {
  const result = applyNavigationAction(
    caret(8),
    { name: 'moveDown', extend: false },
    {
      ...context,
      rules: [
        fractionEndUpRule,
        {
          id: 'test-fraction-end-down',
          nodeKind: 'fraction',
          at: 'after',
          action: 'moveDown',

          /** Return a denominator destination for the additional rule registered by the existing fixture. */
          resolve: () => 7,
        },
      ],
    },
  )
  assert.deepEqual(result.state.selection, { anchor: 7, focus: 7 })
}

test('the registry accepts another node rule without changing the key handler', verifyRuleRegistration)

/** Verify that grow and shrink restore a backward selection exactly. */
const verifyBackwardSelectionHistory = () => {
  const original = createNavigationState({ anchor: 5, focus: 3 })
  const grown = applyNavigationAction(original, { name: 'grow', extend: false }, context)
  const shrunk = applyNavigationAction(grown.state, { name: 'shrink', extend: false }, context)
  assert.deepEqual(shrunk.state.selection, original.selection)
  assert.deepEqual(original.history, [])
}

test('grow and shrink restore a backward selection exactly', verifyBackwardSelectionHistory)

/** Verify that rules can match a specific slot in the innermost fraction. */
const verifySlotMatching = () => {
  const rules = [
    {
      id: 'test-denominator-up',
      nodeKind: 'fraction' as const,
      at: 'inside' as const,
      slot: 'denominator' as const,
      action: 'moveUp' as const,

      /** Choose a fixture destination according to which nested fraction matched the slot-specific rule. */
      resolve: ({ node }: { node: { end: number } }) => (node.end === 8 ? 5 : 8),
    },
  ]
  const inDenominator = applyNavigationAction(caret(7), { name: 'moveUp', extend: false }, { ...context, rules })
  assert.equal(inDenominator.state.selection.focus, 5)
  const inNumerator = applyNavigationAction(caret(5), { name: 'moveUp', extend: false }, { ...context, rules })
  assert.equal(inNumerator.handled, false)
  const nestedInOuterDenominator = applyNavigationAction(caret(11), { name: 'moveUp', extend: false }, { ...context, rules })
  assert.equal(nestedInOuterDenominator.handled, false)
}

test('rules can match a specific slot in the innermost fraction', verifySlotMatching)

/** Verify that unrelated selection changes discard old growth history. */
const verifyHistoryReset = () => {
  const grown = applyNavigationAction(caret(5), { name: 'grow', extend: false }, context)
  const moved = { ...grown.state, selection: { anchor: 11, focus: 11 } }
  const shrunk = applyNavigationAction(moved, { name: 'shrink', extend: false }, context)
  assert.deepEqual(shrunk.state.selection, moved.selection)
  assert.deepEqual(shrunk.state.history, [])
}

test('unrelated selection changes discard old growth history', verifyHistoryReset)

/** Verify that key decoding distinguishes spatial movement from leaving and growing. */
const verifyKeyDecoding = () => {
  const key = {
    key: 'ArrowUp',
    altKey: false,
    ctrlKey: false,
    metaKey: false,
    shiftKey: false,
    isComposing: false,
  }
  assert.deepEqual(getNavigationAction(key), { name: 'moveUp', extend: false })
  assert.deepEqual(getNavigationAction({ ...key, shiftKey: true }), {
    name: 'moveUp',
    extend: true,
  })
  assert.deepEqual(getNavigationAction({ ...key, altKey: true }), {
    name: 'leave',
    extend: false,
  })
  assert.deepEqual(getNavigationAction({ ...key, altKey: true, shiftKey: true }), {
    name: 'grow',
    extend: false,
  })
  assert.equal(getNavigationAction({ ...key, ctrlKey: true }), undefined)
  assert.equal(getNavigationAction({ ...key, isComposing: true }), undefined)
}

test('key decoding distinguishes spatial movement from leaving and growing', verifyKeyDecoding)
