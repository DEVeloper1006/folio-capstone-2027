/**
 * Define all custom cursor movement and selection behavior. Contains visual arrow navigation, logical selection anchors, vertical return positions, term jumps, structure entry and exit, selection growth history, and rule matching.
 *
 * @file
 */

import type { CursorSelection, NavigationActionName } from './navigation-actions.ts'
import { branchAt, contains, sameSpan, nodeBranches, nodeParentBranch } from './structure.ts'
import type { Branch, NodeKind, Span, Structure, StructureNode } from './structure.ts'

/**
 * Retain the visible selection and history between navigation actions. The logical selection preserves nested endpoints behind a whole-construct highlight; vertical positions map region-start offsets to remembered cursor offsets. Growth history is reused only while lastGrowth matches the visible
 * selection.
 */
export interface NavigationState {
  selection: CursorSelection
  history: CursorSelection[]
  lastGrowth?: CursorSelection
  logicalSelection?: CursorSelection
  verticalPositions?: Record<number, number | undefined>
}

/** Supply a rule with the expression structure, current state, and moving cursor offset. Position follows the logical focus when present; xAt returns a rendered horizontal coordinate or undefined when geometry is unavailable. */
interface ActionContext {
  structure: Structure
  state: NavigationState
  position: number
  xAt: (cursorOffset: number) => number | undefined
  extend?: boolean
}

/** Return either a cursor destination for shared transition handling or a complete state for rules that manage selection anchors, history, or vertical positions. */
type RuleResult = number | NavigationState

/** Extend the action context with a matched layout node and the node's direct editable region containing the cursor, when one exists. */
export interface RuleContext extends ActionContext {
  node: StructureNode
  branch?: Branch
}

/** Match an action at a specific kind of node, optionally restricting its editable-region role. A resolver returns undefined when it cannot handle the matched location so rule dispatch can continue. */
interface NodeNavigationRule {
  id: string
  nodeKind: NodeKind
  at: 'before' | 'after' | 'inside'
  slot?: Branch['role']
  action: NavigationActionName
  resolve: (context: RuleContext) => RuleResult | undefined
}

/** Resolve an action without a node-kind restriction. The resolver inspects the action context itself and returns undefined when another rule or MathLive should handle it. */
interface GeneralNavigationRule {
  id: string
  nodeKind?: never
  action: NavigationActionName
  resolve: (context: ActionContext) => RuleResult | undefined
}

/** Allow either a node-specific or general resolver in the ordered navigation registry. The first rule that returns a result handles the action. */
export type NavigationRule = NodeNavigationRule | GeneralNavigationRule

// Rules choose a destination. Selection extension and DOM updates are shared.

/** Choose the direct cursor boundary nearest the current horizontal position in the target region. Use the region end when geometry is unavailable. */
function getClosestCursorOffset(branch: Branch, context: ActionContext): number {
  const cursorX = context.xAt(context.position)
  if (cursorX === undefined) return branch.end

  let closestOffset = branch.end
  let closestDistance = Infinity

  /** Expose each direct child’s ending offset as a possible cursor destination. */
  const getNodeEndOffset = (node: StructureNode) => node.end

  for (const cursorOffset of [branch.start, ...branch.nodes.map(getNodeEndOffset)]) {
    const candidateCursorX = context.xAt(cursorOffset)
    if (candidateCursorX === undefined) continue
    const horizontalDistance = Math.abs(candidateCursorX - cursorX)
    if (horizontalDistance < closestDistance) {
      closestOffset = cursorOffset
      closestDistance = horizontalDistance
    }
  }
  return closestOffset
}

export const fractionEndUpRule: NodeNavigationRule = {
  id: 'fraction-end-up',
  nodeKind: 'fraction',
  at: 'after',
  action: 'moveUp',

  /** Move from the end of this fraction into its numerator without changing the formula. */
  resolve(context) {
    /** Identify the numerator slot owned by the matched fraction. */
    const isNumerator = (branch: Branch) => branch.owner === context.node && branch.role === 'numerator'

    const numeratorBranch = context.structure.branches.find(isNumerator)
    return numeratorBranch ? getClosestCursorOffset(numeratorBranch, context) : undefined
  },
}

/** Compare both selection endpoints so growth history is reused only for the selection that produced it. */
const sameSelection = (a: CursorSelection, b: CursorSelection) => a.anchor === b.anchor && a.focus === b.focus

/** Return growth history only when the current selection still matches the last expanded selection. */
function getSelectionHistory(navigationState: NavigationState) {
  return navigationState.lastGrowth && sameSelection(navigationState.lastGrowth, navigationState.selection) ? navigationState.history : []
}

/** Select the smallest enclosing expression and remember the previous endpoints so shrinking can restore them. */
function growSelection({ structure, state: navigationState }: ActionContext): NavigationState {
  const { selection } = navigationState
  const selectionHistory = getSelectionHistory(navigationState)
  const enclosingSpan = enclosing(structure, {
    start: Math.min(selection.anchor, selection.focus),
    end: Math.max(selection.anchor, selection.focus),
  })
  if (!enclosingSpan) return { ...navigationState, history: selectionHistory }
  const isBackwardSelection = selection.focus < selection.anchor
  const expandedSelection = {
    anchor: isBackwardSelection ? enclosingSpan.end : enclosingSpan.start,
    focus: isBackwardSelection ? enclosingSpan.start : enclosingSpan.end,
  }
  return {
    selection: expandedSelection,
    history: [...selectionHistory, selection],
    lastGrowth: expandedSelection,
  }
}

/** Restore the previous selection from the current growth sequence, or keep the current selection when no matching history remains. */
function shrinkSelection({ state: navigationState }: ActionContext): NavigationState {
  const selectionHistory = getSelectionHistory(navigationState)
  const previousSelection = selectionHistory.at(-1)
  if (!previousSelection) return { selection: navigationState.selection, history: [] }
  return {
    selection: previousSelection,
    history: selectionHistory.slice(0, -1),
    lastGrowth: previousSelection,
  }
}

export const navigationRules: readonly NavigationRule[] = [
  { id: 'horizontal-left', action: 'moveLeft', resolve: moveLeft },
  { id: 'horizontal-right', action: 'moveRight', resolve: moveRight },
  { id: 'vertical-up', action: 'moveUp', resolve: moveUp },
  { id: 'vertical-down', action: 'moveDown', resolve: moveDown },
  { id: 'select-up', action: 'selectUp', resolve: selectUp },
  { id: 'select-down', action: 'selectDown', resolve: selectDown },
  { id: 'block-start', action: 'blockStart', resolve: blockStart },
  { id: 'block-end', action: 'blockEnd', resolve: blockEnd },
  { id: 'root-start', action: 'rootStart', resolve: rootStart },
  { id: 'root-end', action: 'rootEnd', resolve: rootEnd },
  { id: 'tab-forward', action: 'tabForward', resolve: tabForward },
  { id: 'tab-backward', action: 'tabBackward', resolve: tabBackward },
  {
    id: 'skip-backward',
    action: 'skipBackward',

    /** Move to the preceding term boundary within the current editable slot. */
    resolve: ({ structure, position: cursorOffset }) => jump(structure, cursorOffset, -1),
  },
  {
    id: 'skip-forward',
    action: 'skipForward',

    /** Move to the following term boundary within the current editable slot. */
    resolve: ({ structure, position: cursorOffset }) => jump(structure, cursorOffset, 1),
  },
  {
    id: 'leave-structure',
    action: 'leave',

    /** Move the cursor after the structure that owns the current slot. */
    resolve: ({ structure, position: cursorOffset }) => leave(structure, cursorOffset),
  },
  {
    id: 'enter-structure',
    action: 'enter',

    /** Enter the first editable slot of an adjacent structure. */
    resolve: ({ structure, position: cursorOffset }) => enter(structure, cursorOffset),
  },
  { id: 'grow-selection', action: 'grow', resolve: growSelection },
  { id: 'shrink-selection', action: 'shrink', resolve: shrinkSelection },
]

/** Apply the first matching navigation rule to the nearest eligible node. Return a destination or selection state; return undefined when MathLive should handle the action. */
export function resolveRule(action: NavigationActionName, context: ActionContext, rules: readonly NavigationRule[]): RuleResult | undefined {
  /** Collect the direct nodes from every editable branch for rule matching. */
  const getDirectNodes = (branch: Branch) => branch.nodes

  const nodes = context.structure.branches.flatMap(getDirectNodes)
  for (const rule of rules) {
    if (rule.action !== action) continue
    if (!rule.nodeKind) {
      const ruleResult = rule.resolve(context)
      if (ruleResult !== undefined) return ruleResult
      continue
    }

    /** Order matching nodes from smallest to largest so nested structures take precedence. */
    const compareNodeWidth = (a: StructureNode, b: StructureNode) => a.end - a.start - (b.end - b.start)

    /** Keep nodes whose kind matches the current rule. */
    const matchesNodeKind = (node: StructureNode) => node.kind === rule.nodeKind

    const candidateNodes = nodes.filter(matchesNodeKind).sort(compareNodeWidth)
    for (const node of candidateNodes) {
      /** Find the direct slot of this node that contains the cursor position. */
      const containsCursor = (slot: Branch) => slot.owner === node && slot.start <= context.position && slot.end >= context.position

      const branch = context.structure.branches.find(containsCursor)
      const matchesLocation = rule.at === 'inside' ? branch !== undefined : (rule.at === 'after' ? node.end : node.start) === context.position
      if (!matchesLocation) continue
      // A slot mismatch must not silently redirect to an enclosing fraction.
      if (rule.slot && branch?.role !== rule.slot) break
      const ruleResult = rule.resolve({ ...context, node, branch })
      if (ruleResult !== undefined) return ruleResult
      break
    }
  }
  return undefined
}

/** Jump to the next term end or previous term start within the current slot, stopping at that slot’s boundary. */
export function jump(structure: Structure, cursorOffset: number, direction: -1 | 1) {
  const branch = branchAt(structure, cursorOffset)
  if (!branch) return cursorOffset
  if (direction === 1) {
    /** Find the first term whose end is ahead of the current cursor. */
    const endsAfterCursor = (term: Span) => term.end > cursorOffset

    return branch.terms.find(endsAfterCursor)?.end ?? branch.end
  }

  /** Find the nearest preceding term start when scanning backward. */
  const startsBeforeCursor = (term: Span) => term.start < cursorOffset

  return [...branch.terms].reverse().find(startsBeforeCursor)?.start ?? branch.start
}

/** Return the end of the structure owning the current slot, or keep the cursor still at the outermost level. */
export function leave(structure: Structure, cursorOffset: number) {
  return branchAt(structure, cursorOffset)?.owner?.end ?? cursorOffset
}

/** Enter the first slot of the adjacent compound node, preferring the node ahead of the cursor and otherwise the one ending there. */
export function enter(structure: Structure, cursorOffset: number) {
  const branch = branchAt(structure, cursorOffset)
  if (!branch) return cursorOffset

  /** Find the node immediately preceding the cursor boundary. */
  const endsAtCursor = (candidateNode: StructureNode) => candidateNode.end === cursorOffset

  /** Identify a compound node that begins at or contains the cursor boundary. */
  const isAdjacentCompound = (candidateNode: StructureNode) => {
    /** Determine whether this node owns an editable child slot. */
    const isChildSlot = (childBranch: Branch) => childBranch.owner === candidateNode
    return candidateNode.start <= cursorOffset && candidateNode.end > cursorOffset && structure.branches.some(isChildSlot)
  }

  const node = branch.nodes.find(isAdjacentCompound) ?? branch.nodes.find(endsAtCursor)
  if (!node) return cursorOffset

  /** Find the first editable slot owned by the chosen node. */
  const isNodeSlot = (candidateBranch: Branch) => candidateBranch.owner === node

  return structure.branches.find(isNodeSlot)?.start ?? cursorOffset
}

/** Return the smallest complete subexpression that enlarges the selection. At a cursor boundary, prefer the expression ahead within the deepest editable region before considering the expression behind it. */
export function enclosing(structure: Structure, selection: Span): Span | undefined {
  if (selection.start === selection.end) {
    const branch = branchAt(structure, selection.start)
    /** Prefer a symbol or expression beginning at the cursor in its own region, rather than one ending there in a neighbor. */
    function beginsAtCursor(span: Span) {
      return span.start === selection.start && span.end > selection.end && (!branch || contains(branch, span))
    }
    const forward = structure.spans.find(beginsAtCursor)
    if (forward) return forward
  }
  /** Keep enclosing spans that add at least one cursor position to the selection. */
  const enlargesSelection = (span: Span) => contains(span, selection) && !sameSpan(span, selection)

  const enclosingSpans = structure.spans.filter(enlargesSelection)
  return enclosingSpans[0]
}

/** Return the region that owns this cursor boundary and its adjacent direct node. */
function adjacentNode(structure: Structure, position: number, direction: -1 | 1) {
  const branch = branchAt(structure, position)
  /** Match only direct neighbors; nested post-order offsets are not horizontal siblings. */
  function touchesCursor(node: StructureNode) {
    return (direction === 1 ? node.start : node.end) === position
  }
  return { branch, node: branch?.nodes.find(touchesCursor) }
}

/** Return the preferred upper region for horizontal entry, matching DesQuill's visual-arrow configuration. */
function upperRegion(structure: Structure, node: StructureNode) {
  /** Numerators and superscripts are the upper regions that horizontal arrows visit. */
  function isUpper(branch: Branch) {
    return branch.role === 'numerator' || branch.role === 'superscript'
  }
  return nodeBranches(structure, node).find(isUpper)
}

/** Create a collapsed selection, retaining vertical return positions only when explicitly supplied. */
function pointSelection(position: number, verticalPositions?: Record<number, number | undefined>): NavigationState {
  return { selection: { anchor: position, focus: position }, history: [], verticalPositions }
}

/** Project a nested logical anchor onto whole constructs in the smallest region containing both endpoints. */
function visibleSelection(structure: Structure, logical: CursorSelection): CursorSelection {
  if (logical.anchor === logical.focus) return logical
  const span = { start: Math.min(logical.anchor, logical.focus), end: Math.max(logical.anchor, logical.focus) }
  /** Find a common editable region without assuming numerically adjacent offsets share a parent. */
  function coversSelection(branch: Branch) {
    return contains(branch, span)
  }
  /** Prefer the nearest common region rather than promoting every selection to the root. */
  function deepestFirst(left: Branch, right: Branch) {
    return right.depth - left.depth
  }
  const common = structure.branches.filter(coversSelection).sort(deepestFirst).at(0)
  if (!common) return logical
  const commonNodes = common.nodes
  /** Expand an endpoint inside a direct compound node to the required outer boundary. */
  function project(position: number, isLeft: boolean) {
    /** A boundary at the node's own start or end is already in the containing region. */
    function enclosesPosition(node: StructureNode) {
      return node.start < position && node.end > position
    }
    const node = commonNodes.find(enclosesPosition)
    return node ? (isLeft ? node.start : node.end) : position
  }
  const isForward = logical.focus > logical.anchor
  return { anchor: project(logical.anchor, isForward), focus: project(logical.focus, !isForward) }
}

/** Keep the original nested anchor separately from the visible whole-construct highlight. */
function extendSelection(context: ActionContext, logical: CursorSelection): NavigationState {
  return { selection: visibleSelection(context.structure, logical), logicalSelection: logical, history: [] }
}

/** Extend by a whole adjacent node or out of the current region, restoring the anchor's inner region when reversing a structural selection. */
function extendHorizontal(context: ActionContext, direction: -1 | 1): NavigationState {
  const logical = context.state.logicalSelection ?? context.state.selection
  const { branch, node } = adjacentNode(context.structure, logical.focus, direction)
  const destination = node ? (direction === 1 ? node.end : node.start) : branch?.owner ? (direction === 1 ? branch.owner.end : branch.owner.start) : logical.focus
  let next = extendSelection(context, { anchor: logical.anchor, focus: destination })
  const previous = context.state.selection
  const sameHighlight = Math.min(next.selection.anchor, next.selection.focus) === Math.min(previous.anchor, previous.focus) && Math.max(next.selection.anchor, next.selection.focus) === Math.max(previous.anchor, previous.focus)
  if (sameHighlight && node) {
    /** Find the original anchor's direct child region when reversing past a whole selected structure. */
    function containsAnchor(slot: Branch) {
      return slot.start <= logical.anchor && slot.end >= logical.anchor
    }
    const originalRegion = nodeBranches(context.structure, node).find(containsAnchor)
    if (originalRegion) next = extendSelection(context, { anchor: logical.anchor, focus: direction === 1 ? originalRegion.start : originalRegion.end })
  }
  return next
}

/** Leave a region horizontally; ordinary multi-region constructs visit their sibling regions, while visual fraction/script movement exits the construct. */
function exitRegion(structure: Structure, branch: Branch, direction: -1 | 1): number | undefined {
  if (!branch.owner) return undefined
  const slots = nodeBranches(structure, branch.owner)
  const siblingIndex = slots.indexOf(branch) + direction
  const sibling = siblingIndex >= 0 ? slots.at(siblingIndex) : undefined
  if (!upperRegion(structure, branch.owner) && sibling) return direction === 1 ? sibling.start : sibling.end
  return direction === 1 ? branch.owner.end : branch.owner.start
}

/** Move visually across direct siblings, entering the numerator or superscript instead of traversing every serialized offset. */
function moveHorizontal(context: ActionContext, direction: -1 | 1): RuleResult {
  if (context.extend) return extendHorizontal(context, direction)
  const { selection } = context.state
  if (selection.anchor !== selection.focus) return direction === 1 ? Math.max(selection.anchor, selection.focus) : Math.min(selection.anchor, selection.focus)
  const { branch, node } = adjacentNode(context.structure, context.position, direction)
  if (!branch) return context.position
  if (!node) return exitRegion(context.structure, branch, direction) ?? context.position
  const slots = nodeBranches(context.structure, node)
  const destination = upperRegion(context.structure, node) ?? (direction === 1 ? slots[0] : slots.at(-1))
  return destination ? (direction === 1 ? destination.start : destination.end) : direction === 1 ? node.end : node.start
}

/** Move one horizontal position left or structurally extend left when Shift is held. */
function moveLeft(context: ActionContext) {
  return moveHorizontal(context, -1)
}

/** Move one horizontal position right or structurally extend right when Shift is held. */
function moveRight(context: ActionContext) {
  return moveHorizontal(context, 1)
}

/** Find the upper/lower region of a fraction, script, or large operator; roots expose a vertical pair only when they have an index. */
function verticalRegion(structure: Structure, node: StructureNode, direction: -1 | 1) {
  const slots = nodeBranches(structure, node)
  /** Match the structural role rather than branch serialization order. */
  function matchesDirection(branch: Branch) {
    return direction === -1 ? branch.role === 'numerator' || branch.role === 'superscript' : branch.role === 'denominator' || branch.role === 'subscript'
  }
  if (node.kind === 'root' && slots.length === 2) return direction === -1 ? slots[0] : slots[1]
  return slots.find(matchesDirection)
}

/** Restore a prior cursor in the destination region, or choose its nearest horizontal position. Remember nested source positions under their enclosing region. */
function jumpVertical(context: ActionContext, source: Branch, destination: Branch): NavigationState {
  const positions = { ...context.state.verticalPositions, [source.start]: context.position }
  const cached = positions[destination.start]
  const cursorOffset = cached !== undefined && destination.start <= cached && cached <= destination.end ? cached : getClosestCursorOffset(destination, context)
  return pointSelection(cursorOffset, positions)
}

/** Determine whether this cursor is at the final nested boundary before leaving a script's parent. */
function isAtRegionEnd(structure: Structure, position: number, branch: Branch, ancestor: Branch): boolean {
  let current: Branch | undefined = branch
  let cursorOffset = position
  while (current) {
    if (cursorOffset !== current.end) return false
    if (current === ancestor) return true
    if (!current.owner) return false
    cursorOffset = current.owner.end
    current = nodeParentBranch(structure, current.owner)
  }
  return false
}

/** Enter an adjacent upper/lower region, move between related regions, or ascend through nesting until a vertical relationship is found. */
function moveVertical(context: ActionContext, direction: -1 | 1): RuleResult | undefined {
  const right = adjacentNode(context.structure, context.position, 1)
  const left = adjacentNode(context.structure, context.position, -1)
  const rightRegion = right.node && verticalRegion(context.structure, right.node, direction)
  const leftRegion = left.node && verticalRegion(context.structure, left.node, direction)
  if (rightRegion || leftRegion) return pointSelection(rightRegion ? rightRegion.start : leftRegion!.end, context.state.verticalPositions)
  const initial = branchAt(context.structure, context.position)
  let branch = initial
  while (branch?.owner) {
    const owner = branch.owner
    const slots = nodeBranches(context.structure, owner)
    if (owner.kind === 'array') {
      if (branch.row === undefined || branch.column === undefined) return undefined
      /** Preserve the current column when moving between matrix or cases rows. */
      function matchesCell(candidate: Branch) {
        return candidate.row === branch!.row! + direction && candidate.column === branch!.column
      }
      const destination = slots.find(matchesCell)
      if (destination) return jumpVertical(context, branch, destination)
    }
    const opposite = verticalRegion(context.structure, owner, direction === -1 ? 1 : -1)
    if (opposite === branch) {
      const destination = verticalRegion(context.structure, owner, direction)
      if (destination) return jumpVertical(context, branch, destination)
    }
    const exitsScript = (owner.kind === 'scripts' || owner.kind === 'operator') && (direction === 1 ? branch.role === 'superscript' : branch.role === 'subscript')
    if (exitsScript && !verticalRegion(context.structure, owner, direction)) return pointSelection(initial && isAtRegionEnd(context.structure, context.position, initial, branch) ? owner.end : owner.start)
    branch = nodeParentBranch(context.structure, owner)
  }
  return pointSelection(context.state.selection.focus, context.state.verticalPositions)
}

/** Move upward through structural regions while preserving vertical return positions. */
function moveUp(context: ActionContext) {
  return moveVertical(context, -1)
}

/** Move downward through structural regions while preserving vertical return positions. */
function moveDown(context: ActionContext) {
  return moveVertical(context, 1)
}

/** Extend toward the current region's boundary; optionally expand out of the region when already at its boundary. */
function selectBoundary(context: ActionContext, direction: -1 | 1, expandAtBoundary: boolean): NavigationState {
  let state = context.state
  let position = state.logicalSelection?.focus ?? state.selection.focus
  let branch = branchAt(context.structure, position)
  if (!branch) return state
  if (position === (direction === 1 ? branch.end : branch.start)) return expandAtBoundary ? extendHorizontal({ ...context, state, position }, direction) : state
  for (let count = 0; count <= context.structure.spans.length * 2; count++) {
    state = extendHorizontal({ ...context, state, position }, direction)
    const nextPosition = state.logicalSelection?.focus ?? state.selection.focus
    if (nextPosition === position) break
    position = nextPosition
    branch = branchAt(context.structure, position)
    if (!branch || position === (direction === 1 ? branch.end : branch.start)) break
  }
  return state
}

/** Select toward the beginning of the current region, expanding outward only when already there. */
function selectUp(context: ActionContext) {
  return selectBoundary(context, -1, true)
}

/** Select toward the end of the current region, expanding outward only when already there. */
function selectDown(context: ActionContext) {
  return selectBoundary(context, 1, true)
}

/** Move to or select toward the beginning of the current editable region. */
function blockStart(context: ActionContext) {
  return context.extend ? selectBoundary(context, -1, false) : branchAt(context.structure, context.position)?.start
}

/** Move to or select toward the end of the current editable region. */
function blockEnd(context: ActionContext) {
  return context.extend ? selectBoundary(context, 1, false) : branchAt(context.structure, context.position)?.end
}

/** Move to the beginning of the expression, preserving a nested logical anchor when extending. */
function rootStart(context: ActionContext) {
  const anchor = context.state.logicalSelection?.anchor ?? context.state.selection.anchor
  return context.extend ? extendSelection(context, { anchor, focus: 0 }) : 0
}

/** Move to the expression's final offset, preserving a nested logical anchor when extending. */
function rootEnd(context: ActionContext) {
  const end = context.structure.branches[0]?.end ?? context.position
  const anchor = context.state.logicalSelection?.anchor ?? context.state.selection.anchor
  return context.extend ? extendSelection(context, { anchor, focus: end }) : end
}

/** Select the next unfilled placeholder in serialization order, excluding the currently selected one. Return undefined when ordinary region navigation should continue. */
function placeholderDestination(context: ActionContext, direction: -1 | 1): NavigationState | undefined {
  const { anchor, focus } = context.state.selection
  const boundary = direction === 1 ? Math.max(anchor, focus) : Math.min(anchor, focus)
  /** Collect direct nodes once per editable region. */
  function directNodes(branch: Branch) {
    return branch.nodes
  }
  /** Find unfilled placeholders ahead of or behind the current selection. */
  function inDirection(node: StructureNode) {
    return node.kind === 'placeholder' && (direction === 1 ? node.start >= boundary : node.end <= boundary)
  }
  /** Prefer the nearest eligible placeholder in the requested direction. */
  function byOffset(left: StructureNode, right: StructureNode) {
    return direction * (left.end - right.end)
  }
  const destination = context.structure.branches.flatMap(directNodes).filter(inDirection).sort(byOffset).at(0)
  return destination ? { selection: { anchor: destination.start, focus: destination.end }, history: [] } : undefined
}

/** Select the next placeholder before exiting the current region; unhandled root-level Tab retains native focus traversal. */
function tabForward(context: ActionContext) {
  const branch = branchAt(context.structure, context.position)
  return placeholderDestination(context, 1) ?? (branch && exitRegion(context.structure, branch, 1))
}

/** Select the previous placeholder before exiting the current region; unhandled root-level Shift-Tab retains native focus traversal. */
function tabBackward(context: ActionContext) {
  const branch = branchAt(context.structure, context.position)
  return placeholderDestination(context, -1) ?? (branch && exitRegion(context.structure, branch, -1))
}
