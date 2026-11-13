/**
 * Check the structure area. Contains recorded MathLive snapshots and assertions for term jumps, nesting, selection growth, and empty slots.
 *
 * @file
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'
import { branchAt, buildStructure } from './structure.ts'
import { enclosing, enter, jump, leave } from '../navigation/navigation-rules.ts'
import type { ElementSnapshot, Span } from './structure.ts'

/** Convert recorded MathLive depth and LaTeX pairs into element snapshots for the existing navigation fixtures. */
function snapshot(entries: Array<[number, string]>): ElementSnapshot[] {
  /** Preserve each recorded nesting depth and LaTeX value in a named snapshot object. */
  const snapshotFromEntry = ([depth, latex]: [number, string]) => ({
    depth,
    latex,
  })

  return entries.map(snapshotFromEntry)
}

// Public getElementInfo() snapshots from MathLive 0.111.4.
const fractions = buildStructure(
  snapshot([
    [0, ''],
    [1, ''],
    [1, '1'],
    [1, ''],
    [1, '2'],
    [0, '\\frac{1}{2}'],
    [0, '+'],
    [1, ''],
    [1, '1'],
    [1, ''],
    [1, '3'],
    [0, '\\frac{1}{3}'],
    [0, '+'],
    [0, 'x'],
  ]),
)
const nested = buildStructure(
  snapshot([
    [0, ''],
    [1, ''],
    [1, 'a'],
    [1, '+'],
    [2, ''],
    [2, 'b'],
    [2, ''],
    [2, 'c'],
    [1, '\\frac{b}{c}'],
    [1, ''],
    [1, 'd'],
    [0, '\\frac{a+\\frac{b}{c}}{d}'],
    [0, '+'],
    [0, 'e'],
  ]),
)

/** Create a span from explicit start and end offsets for the existing selection assertions. */
const range = (start: number, end: number): Span => ({ start, end })

/** Verify that term jumps skip entire fractions and intervening operators. */
const verifyTermJumps = () => {
  assert.equal(jump(fractions, 0, 1), 5)
  assert.equal(jump(fractions, 5, 1), 11)
  assert.equal(jump(fractions, 11, 1), 13)
  assert.equal(jump(fractions, 13, -1), 12)
  assert.equal(jump(fractions, 12, -1), 6)
  assert.equal(jump(fractions, 6, -1), 0)
}

test('term jumps skip entire fractions and intervening operators', verifyTermJumps)

/** Verify that jumps stay within the current slot until explicitly leaving. */
const verifySlotBoundaries = () => {
  assert.equal(jump(nested, 4, 1), 5)
  assert.equal(jump(nested, 5, 1), 5)
  assert.equal(jump(nested, 5, -1), 4)
  assert.equal(leave(nested, 5), 8)
  assert.equal(leave(nested, 8), 11)
  assert.equal(leave(nested, 11), 11)
}

test('jumps stay within the current slot until explicitly leaving', verifySlotBoundaries)

/** Verify that uneven nesting identifies sibling terms in the correct branch. */
const verifyUnevenNesting = () => {
  assert.deepEqual(branchAt(nested, 2)?.terms, [range(1, 2), range(3, 8)])
  assert.equal(jump(nested, 2, 1), 8)
  assert.equal(jump(nested, 0, 1), 11)
  assert.equal(enter(nested, 0), 1)
  assert.equal(enter(nested, 3), 4)
}

test('uneven nesting identifies sibling terms in the correct branch', verifyUnevenNesting)

/** Verify that selection grows through actual enclosing slots and constructs. */
const verifySelectionGrowth = () => {
  let selection = range(5, 5)
  for (const expected of [range(4, 5), range(3, 8), range(1, 8), range(0, 11), range(0, 13)]) {
    const larger = enclosing(nested, selection)
    assert.ok(larger)
    assert.deepEqual(range(larger.start, larger.end), expected)
    selection = larger
  }
  assert.equal(enclosing(nested, selection), undefined)
}

test('selection grows through actual enclosing slots and constructs', verifySelectionGrowth)

/** Verify that selection spanning numerator and denominator expands to the whole fraction. */
const verifyFractionSelection = () => {
  const larger = enclosing(fractions, range(2, 4))
  assert.ok(larger)
  assert.deepEqual(range(larger.start, larger.end), range(0, 5))
}

test('selection spanning numerator and denominator expands to the whole fraction', verifyFractionSelection)

/** Verify that growing at the start of a term selects that term before its ancestors. */
const verifyGrowthAtTermStart = () => {
  const fraction = enclosing(fractions, range(6, 6))
  const symbol = enclosing(fractions, range(12, 12))
  assert.ok(fraction)
  assert.ok(symbol)
  assert.deepEqual(range(fraction.start, fraction.end), range(6, 11))
  assert.deepEqual(range(symbol.start, symbol.end), range(12, 13))
}

test('growing at the start of a term selects that term before its ancestors', verifyGrowthAtTermStart)

/** Verify that entering can reenter an adjacent fraction but leaves a plain symbol alone. */
const verifyAdjacentEntry = () => {
  assert.equal(enter(fractions, 5), 1)
  assert.equal(enter(fractions, 13), 13)
}

test('entering can reenter an adjacent fraction but leaves a plain symbol alone', verifyAdjacentEntry)

/** Verify that empty slots remain navigable without manufacturing a selection. */
const verifyEmptySlots = () => {
  const empty = buildStructure(
    snapshot([
      [0, ''],
      [1, ''],
      [1, ''],
      [0, '\\frac{}{}'],
    ]),
  )
  assert.equal(enter(empty, 0), 1)
  assert.equal(jump(empty, 1, 1), 1)
  assert.equal(leave(empty, 1), 3)
  assert.equal(enclosing(buildStructure(snapshot([[0, '']])), range(0, 0)), undefined)
}

test('empty slots remain navigable without manufacturing a selection', verifyEmptySlots)
