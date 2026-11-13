/**
 * Recover syntactic subexpression ranges from each editable region's direct nodes. Contains precedence-based grouping, balanced delimiters, function calls, scripts, and quantifier scopes without rewriting LaTeX or evaluating mathematics.
 *
 * @file
 */

import type { Span, StructureNode } from './structure.ts'

const spacingPattern = /^(?:\\[,;!: ]|\\(?:quad|qquad))$/
const quantifierPattern = /^\\(?:forall|exists|nexists)$/
const namedFunctionPattern = /^\\(?:sin|cos|tan|sec|csc|cot|sinh|cosh|tanh|log|ln|exp|arcsin|arccos|arctan|operatorname\{[^}]+\})$/
const closingDelimiters: Record<string, string | undefined> = { '(': ')', '[': ']', '\\{': '\\}', '\\lbrace': '\\rbrace', '\\langle': '\\rangle', '\\lvert': '\\rvert', '\\lVert': '\\rVert' }
const closePattern = /^(?:[)\]]|\\(?:\}|rbrace|rangle|rvert|rVert))$/

/** Assign conventional binding strengths; larger values bind more tightly. Unknown adjacent atoms are handled as implicit multiplication. */
function precedence(latex: string): number | undefined {
  if (/^\\(?:Leftrightarrow|leftrightarrow|iff)$/.test(latex)) return 10
  if (/^\\(?:Rightarrow|rightarrow|Leftarrow|implies|impliedby)$/.test(latex)) return 20
  if (/^\\(?:lor|vee)$/.test(latex)) return 30
  if (/^\\(?:land|wedge)$/.test(latex)) return 40
  if (/^(?:[=<>]|\\(?:leq?|geq?|neq?|approx|equiv|in|notin|subseteq?|supseteq?|to|mid))$/.test(latex)) return 50
  if (/^\\(?:cup|cap|setminus)$/.test(latex)) return 60
  if (/^(?:[+-]|\\(?:pm|mp))$/.test(latex)) return 70
  if (/^(?:[*/]|\\(?:times|cdot|div))$/.test(latex)) return 80
  return undefined
}

/** Collect complete syntactic units within a single editable region. Delimiter contents and argument lists are parsed separately; incomplete input keeps its recoverable units. */
export function selectionSpans(nodes: readonly StructureNode[]): Span[] {
  /** Ignore presentation spacing when locating expression boundaries. */
  function isContent(node: StructureNode) {
    return !spacingPattern.test(node.latex)
  }
  const tokens = nodes.filter(isContent)
  const spans: Span[] = []
  let index = 0

  /** Record a nonempty range without changing the original nodes or formula. */
  function remember(span: Span): Span {
    if (span.end > span.start) spans.push(span)
    return span
  }

  /** Attach each following script atom to its base, including scripts after complete calls or parenthesized expressions. */
  function readScripts(base: Span): Span {
    let span = base
    while (tokens[index]?.kind === 'scripts') span = remember({ start: span.start, end: tokens[index++].end })
    return span
  }

  /** Parse comma-separated arguments or top-level expressions, stopping at a closing delimiter. Always advance past unsupported punctuation. */
  function readSequence() {
    while (index < tokens.length && !closePattern.test(tokens[index].latex)) {
      const previous = index
      readExpression(0)
      if (index === previous || /^[,;:]$/.test(tokens[index]?.latex ?? '')) index++
    }
  }

  /** Read balanced literal delimiters; function calls own their parentheses, while standalone grouped expressions also expose the enclosing range. */
  function readDelimited(includeGroup: boolean): Span | undefined {
    const opening = tokens[index++]
    readSequence()
    if (tokens[index]?.latex !== closingDelimiters[opening.latex]) return undefined
    const end = tokens[index++].end
    const span = { start: opening.start, end }
    return includeGroup ? remember(span) : span
  }

  /** Read one bound variable or domain atom, then the quantified body. Quantifiers bind the following formula within the current delimiter or region. */
  function readQuantifier(): Span {
    const quantifier = tokens[index++]
    if (tokens[index]?.latex === '!') index++
    let binder = readPrimary(false)
    while (tokens[index]?.latex === ',') {
      index++
      binder = readPrimary(false) ?? binder
    }
    if (/^\\(?:in|notin)$/.test(tokens[index]?.latex ?? '')) {
      index++
      binder = readPrimary(false) ?? binder
      while (/^\\(?:cup|cap|setminus)$/.test(tokens[index]?.latex ?? '')) {
        index++
        binder = readPrimary(false) ?? binder
      }
    }
    if (binder) remember({ start: quantifier.start, end: binder.end })
    if (/^[:;]$/.test(tokens[index]?.latex ?? '')) index++
    const body = readExpression(0)
    return body ? remember({ start: quantifier.start, end: body.end }) : { start: quantifier.start, end: binder?.end ?? quantifier.end }
  }

  /** Read a symbol, number, construct, function call, or prefix expression. Attach scripts to their base so growth never selects a bare script suffix. */
  function readPrimary(allowCall = true): Span | undefined {
    const node = tokens.at(index)
    if (!node || closePattern.test(node.latex) || /^[,;:]$/.test(node.latex)) return undefined
    if (quantifierPattern.test(node.latex)) return readQuantifier()
    if (/^(?:[+-]|\\(?:neg|lnot|pm|mp))$/.test(node.latex)) {
      index++
      const body = readPrimary()
      return body ? remember({ start: node.start, end: body.end }) : undefined
    }
    if (precedence(node.latex) !== undefined || node.kind === 'scripts') return undefined
    if (closingDelimiters[node.latex]) {
      const group = readDelimited(true)
      return group && readScripts(group)
    }
    index++
    let span: Span = { start: node.start, end: node.end }
    if (/^[0-9.]$/.test(node.latex)) {
      while (/^[0-9.]$/.test(tokens[index]?.latex ?? '')) span = { start: node.start, end: tokens[index++].end }
    }
    remember(span)
    span = readScripts(span)
    const callable = /^[a-zA-Z]$/.test(node.latex) || namedFunctionPattern.test(node.latex)
    if (allowCall && callable) {
      if (tokens[index]?.latex === '(') {
        const argumentsSpan = readDelimited(false)
        if (argumentsSpan) span = remember({ start: span.start, end: argumentsSpan.end })
      } else if (/^\\left\(/.test(tokens[index]?.latex ?? '')) {
        span = remember({ start: span.start, end: tokens[index++].end })
      } else if (namedFunctionPattern.test(node.latex)) {
        const argument = readPrimary()
        if (argument) span = remember({ start: span.start, end: argument.end })
      }
    }
    return readScripts(span)
  }

  /** Group operands by operator precedence, treating implication as right-associative and adjacent factors as multiplication. Exclude dangling operators from recovered expressions. */
  function readExpression(minimum: number): Span | undefined {
    let left = readPrimary()
    if (!left) return undefined
    while (index < tokens.length) {
      const token = tokens[index]
      if (closePattern.test(token.latex) || /^[,;:]$/.test(token.latex)) break
      const explicit = precedence(token.latex)
      const strength = explicit ?? 80
      if (strength < minimum) break
      if (explicit !== undefined) index++
      const previous = index
      const right = readExpression(strength + (strength === 20 ? 0 : 1))
      if (!right || index === previous) break
      left = remember({ start: left.start, end: right.end })
    }
    return left
  }

  readSequence()
  return spans
}
