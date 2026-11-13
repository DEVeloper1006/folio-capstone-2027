/**
 * Recover editable layout structure from MathLive element metadata. Contains span and node types, branch ownership, fraction and script roles, matrix-cell coordinates, syntactic selection ranges, and structural queries.
 *
 * @file
 */

import { selectionSpans } from './selection-spans.ts'

/** Bound a region by MathLive cursor offsets, including both boundary positions. These offsets describe the editor layout, not character indices in the LaTeX source. */
export interface Span {
  start: number
  end: number
}

/** Capture one MathLive offset's nesting depth and serialized LaTeX. An empty LaTeX value marks the starting sentinel of an editable region. */
export interface ElementSnapshot {
  depth: number
  latex: string
}

/** Classify layout constructs for navigation rules. The other kind includes ordinary symbols and constructs without a dedicated classification. */
export type NodeKind = 'fraction' | 'scripts' | 'operator' | 'root' | 'array' | 'group' | 'placeholder' | 'other'

/** Describe one symbol or compound construct, spanning from the cursor before it to the cursor after it. Its serialized LaTeX and nesting depth identify its kind and containing region. */
export interface StructureNode extends Span {
  kind: NodeKind
  depth: number
  latex: string
}

/** Describe an editable region such as a numerator, exponent, or matrix cell. The owner is absent for the expression's outermost region; nodes are direct children, and terms are spans used for term jumps. Matrix row and column coordinates are zero-based and omitted when recovery is ambiguous. */
export interface Branch extends Span {
  role?: 'numerator' | 'denominator' | 'superscript' | 'subscript' | 'index' | 'body' | 'cell'
  row?: number
  column?: number
  depth: number
  owner?: StructureNode
  nodes: StructureNode[]
  terms: Span[]
}

/** Collect the expression's editable regions and selection-growth candidates. Candidate spans are nonempty, deduplicated, and ordered from narrowest to widest. */
export interface Structure {
  branches: Branch[]
  spans: Span[]
}

const termSeparatorPattern = /^(?:[+\-=<>,;:]|\\(?:pm|mp|times|cdot|div|leq?|geq?|neq|approx|equiv|in|notin|subseteq?|supseteq?|land|lor|wedge|vee|Rightarrow|Leftrightarrow|implies|iff|to|cup|cap))$/
const spacingCommandPattern = /^(?:\\[,;!: ]|\\(?:quad|qquad))$/

/** Determine whether the outer span includes both endpoints of the inner span. */
export const contains = (outer: Span, inner: Span) => outer.start <= inner.start && outer.end >= inner.end

/** Determine whether two spans have identical start and end offsets. */
export const sameSpan = (a: Span, b: Span) => a.start === b.start && a.end === b.end

// MathLive exposes a post-order walk: children precede their enclosing atom,
// and each editable branch starts with an empty sentinel at its own depth.

/** Reconstruct layout nodes, editable slots, and enclosing spans from MathLive’s public post-order element metadata. This describes presentation structure rather than a complete mathematical meaning. */
export function buildStructure(elementSnapshots: ElementSnapshot[]): Structure {
  const nodes: StructureNode[] = []
  const branches: Branch[] = []

  for (let cursorOffset = 0; cursorOffset < elementSnapshots.length; cursorOffset++) {
    const elementSnapshot = elementSnapshots[cursorOffset]
    if (!elementSnapshot.latex) {
      let branchEndOffset = cursorOffset + 1
      while (branchEndOffset < elementSnapshots.length && elementSnapshots[branchEndOffset].depth >= elementSnapshot.depth && !(elementSnapshots[branchEndOffset].depth === elementSnapshot.depth && !elementSnapshots[branchEndOffset].latex)) {
        branchEndOffset++
      }
      branches.push({
        start: cursorOffset,
        end: branchEndOffset - 1,
        depth: elementSnapshot.depth,
        nodes: [],
        terms: [],
      })
      continue
    }

    let nodeStartOffset = cursorOffset - 1
    while (nodeStartOffset > 0 && elementSnapshots[nodeStartOffset].depth > elementSnapshot.depth) nodeStartOffset--
    nodes.push({
      start: nodeStartOffset,
      end: cursorOffset,
      kind: getNodeKind(elementSnapshot.latex),
      ...elementSnapshot,
    })
  }

  for (const branch of branches) {
    /** Find the first following atom at a shallower depth that owns this editable branch. */
    const isBranchOwner = (node: StructureNode) => node.end > branch.end && node.depth < branch.depth

    branch.owner = nodes.find(isBranchOwner)

    /** Keep direct nodes at this branch’s depth whose spans remain inside the branch. */
    const isDirectNode = (node: StructureNode) => node.depth === branch.depth && contains(branch, node)

    branch.nodes = nodes.filter(isDirectNode)

    let currentTerm: Span | undefined
    for (const node of branch.nodes) {
      if (termSeparatorPattern.test(node.latex)) {
        if (currentTerm) branch.terms.push(currentTerm)
        currentTerm = undefined
      } else if (!spacingCommandPattern.test(node.latex)) {
        currentTerm = { start: currentTerm?.start ?? node.start, end: node.end }
      }
    }
    if (currentTerm) branch.terms.push(currentTerm)
  }

  for (const node of nodes) {
    /** Collect this construct's direct editable regions in MathLive's post-order serialization. */
    const isOwnedSlot = (branch: Branch) => branch.owner === node
    const slots = branches.filter(isOwnedSlot)
    if (node.kind === 'fraction') {
      if (slots[0]) slots[0].role = 'numerator'
      if (slots[1]) slots[1].role = 'denominator'
    } else if (node.kind === 'scripts' || node.kind === 'operator') {
      const roles = getScriptRoles(node.latex)
      for (let index = 0; index < slots.length; index++) slots[index].role = roles[index]
    } else if (node.kind === 'root') {
      if (slots.length > 1) slots[0].role = 'index'
      if (slots.at(-1)) slots.at(-1)!.role = 'body'
    } else if (node.kind === 'array') {
      const cells = getArrayCells(node.latex)
      for (let index = 0; index < slots.length; index++) {
        slots[index].role = 'cell'
        if (cells.length === slots.length) Object.assign(slots[index], cells[index])
      }
    } else {
      for (const slot of slots) slot.role = 'body'
    }
  }

  /** Keep only the first occurrence of each pair of span boundaries. */
  const isUniqueSpan = (span: Span, spanIndex: number, candidateSpans: Span[]) => {
    /** Locate the first span with the same start and end offsets. */
    const matchesSpan = (otherSpan: Span) => sameSpan(span, otherSpan)
    return candidateSpans.findIndex(matchesSpan) === spanIndex
  }

  /** Order spans by width so selection growth reaches the smallest enclosing expression first. */
  const compareSpanWidth = (a: Span, b: Span) => a.end - a.start - (b.end - b.start)

  /** Discard empty spans that cannot enlarge a selection. */
  const isNonemptySpan = (span: Span) => span.end > span.start

  /** Recover expression boundaries separately from term-jump separators so calls, logical clauses, and quantifier scopes remain intact. */
  const getSelectionSpans = (branch: Branch) => selectionSpans(branch.nodes)

  const spans = [...branches.flatMap(getSelectionSpans), ...branches].filter(isNonemptySpan).sort(compareSpanWidth).filter(isUniqueSpan)

  return { branches, spans }
}

/** Find the deepest editable branch containing the cursor, or return undefined when no branch contains it. */
export function branchAt(structure: Structure, cursorOffset: number): Branch | undefined {
  /** Prefer more deeply nested branches when several branches contain the same position. */
  const compareBranchDepth = (a: Branch, b: Branch) => b.depth - a.depth

  /** Keep branches whose boundaries contain the cursor position. */
  const containsPosition = (branch: Branch) => branch.start <= cursorOffset && branch.end >= cursorOffset

  return structure.branches.filter(containsPosition).sort(compareBranchDepth)[0]
}

/** Classify layout constructs from their own serialized command, without interpreting mathematical meaning. */
function getNodeKind(latex: string): NodeKind {
  if (/^\\placeholder\{\}$/.test(latex)) return 'placeholder'
  if (/^\\(?:frac|dfrac|tfrac|cfrac|binom|dbinom|tbinom)\b/.test(latex)) return 'fraction'
  if (/^[_^]/.test(latex)) return 'scripts'
  if (/^\\(?:sum|prod|coprod|int|iint|iiint|oint|bigcup|bigcap|lim|bigvee|bigwedge)(?![a-zA-Z])/.test(latex)) return 'operator'
  if (/^\\sqrt\b/.test(latex)) return 'root'
  if (/^\\begin\{/.test(latex)) return 'array'
  if (/^\\left\b/.test(latex)) return 'group'
  return 'other'
}

/** Read only top-level script markers so a nested exponent does not become a sibling region. */
function getScriptRoles(latex: string): NonNullable<Branch['role']>[] {
  const roles: NonNullable<Branch['role']>[] = []
  let depth = 0
  for (let index = 0; index < latex.length; index++) {
    if (latex[index - 1] === '\\') continue
    const character = latex[index]
    if (character === '{') depth++
    else if (character === '}') depth--
    else if (depth === 0 && (character === '_' || character === '^')) roles.push(character === '_' ? 'subscript' : 'superscript')
  }
  return roles
}

/** Recover array-cell coordinates while ignoring separators in nested environments and braced arguments. Reject ambiguous counts at the caller. */
function getArrayCells(latex: string): Array<{ row: number; column: number }> {
  const body = latex.replace(/^\\begin\{[^}]+\}(?:\{[^}]*\})?/, '').replace(/\\end\{[^}]+\}$/, '')
  const cells = [{ row: 0, column: 0 }]
  let row = 0
  let column = 0
  let depth = 0
  let environments = 0
  for (let index = 0; index < body.length; index++) {
    const remaining = body.slice(index)
    const environment = remaining.match(/^\\(begin|end)\{[^}]+\}/)
    if (environment) {
      environments += environment[1] === 'begin' ? 1 : -1
      index += environment[0].length - 1
      continue
    }
    if (body[index] === '\\' && body[index + 1] === '\\') {
      if (!depth && !environments) {
        row++
        column = 0
        cells.push({ row, column })
      }
      index++
    } else if (body[index] === '\\') index++
    else if (body[index] === '{') depth++
    else if (body[index] === '}') depth--
    else if (body[index] === '&' && !depth && !environments) {
      column++
      cells.push({ row, column })
    }
  }
  return cells
}

/** Return the direct editable regions owned by one layout construct. */
export function nodeBranches(structure: Structure, node: StructureNode): Branch[] {
  /** Match the construct by identity within the current structure snapshot. */
  function ownedByNode(branch: Branch) {
    return branch.owner === node
  }
  return structure.branches.filter(ownedByNode)
}

/** Find the region that directly contains a node, rather than one of that node's own child regions. */
export function nodeParentBranch(structure: Structure, node: StructureNode): Branch | undefined {
  /** A direct child is present in exactly one recovered branch's node list. */
  function containsNode(branch: Branch) {
    return branch.nodes.includes(node)
  }
  return structure.branches.find(containsNode)
}
