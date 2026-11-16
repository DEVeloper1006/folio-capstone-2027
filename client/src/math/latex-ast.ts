/**
 * Convert between LaTeX and structural MathJSON with the same parser and printer in the browser and Python.
 *
 * @file
 */

import { ComputeEngine, isFunction } from '@cortex-js/compute-engine'
import type { Expression } from '@cortex-js/compute-engine'
import type { MathJsonExpression } from '@cortex-js/compute-engine/math-json'

// Cortex can silently discard empty groups and matrix entries, or interpret display lines and ellipses as a list or range.
const incompleteNotation = /\{\s*\}|\\(?:[clvd]dots|dots[a-z]*|placeholder)\b|\.{3}|…|\\begin\s*\{(?:align(?:ed|at|edat)?|gather(?:ed)?|multline|split|eqnarray)\*?\}|&\s*(?=\\\\|\\end\b)|[,;]\s*$/

/** Check matrix dimensions before Cortex normalizes a partially filled grid. */
function isRectangular(matrix: Expression): boolean {
  if (!isFunction(matrix) || !isFunction(matrix.op1, 'List')) return false
  const rows = matrix.op1.ops
  const firstRow = rows.at(0)
  if (!firstRow || !isFunction(firstRow, 'List') || firstRow.nops === 0) return false
  for (const row of rows) {
    if (!isFunction(row, 'List') || row.nops !== firstRow.nops) return false
  }
  return true
}

/** Reject parser errors, layout placeholders, and incomplete operands anywhere in the tree. */
function isComplete(expression: Expression): boolean {
  return expression.isValid && !expression.has(['Nothing', 'ContinuationPlaceholder', 'HorizontalSpacing']) && expression.getSubexpressions('Matrix').every(isRectangular) && expression.canonical.isValid
}

/** Accept compact MathJSON from either runtime. Large exact numbers travel as decimal strings in a num object. */
function isCompactMathJson(value: unknown): value is MathJsonExpression {
  if (typeof value === 'string') return value.length > 0
  if (typeof value === 'number') return Number.isFinite(value) && (!Number.isInteger(value) || Number.isSafeInteger(value))
  if (Array.isArray(value)) return typeof value[0] === 'string' && value[0].length > 0 && value.slice(1).every(isCompactMathJson)
  if (!value || typeof value !== 'object' || Object.keys(value).length !== 1) return false
  if ('num' in value && typeof value.num === 'string') return /^(?:[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:\(\d+\))?(?:e[+-]?\d+)?|[+-]?Infinity|NaN)$/i.test(value.num)
  if ('str' in value) return typeof value.str === 'string'
  if ('sym' in value) return typeof value.sym === 'string' && value.sym.length > 0
  if ('fn' in value) return Array.isArray(value.fn) && isCompactMathJson(value.fn)
  return false
}

/** Parse one complete expression without reducing it or guessing the meaning of an undeclared function call. */
function latexToAst(latex: string): MathJsonExpression | null {
  if (typeof latex !== 'string' || !latex.trim() || incompleteNotation.test(latex)) return null
  const state = { ambiguous: false }

  /** Mark a call whose head could also be a scalar followed by a parenthesized factor. */
  function resolveApplication(): undefined {
    state.ambiguous = true
    return undefined
  }

  const engine = new ComputeEngine()
  try {
    const expression = engine.parse(latex, { form: 'raw', strict: true, diagnostics: true, resolveApplication })
    if (state.ambiguous || !isComplete(expression)) return null
    for (const diagnostic of expression.parseDiagnostics ?? []) {
      if (diagnostic.code !== 'undeclared-symbol') return null
    }
    const ast = expression.json
    return isCompactMathJson(ast) ? ast : null
  } catch {
    return null
  }
}

/** Print a complete tree as LaTeX while preserving operations such as division and subtraction. */
function astToLatex(ast: MathJsonExpression): string | null {
  if (!isCompactMathJson(ast)) return null
  const engine = new ComputeEngine()
  try {
    const expression = engine.expr(ast, { form: 'raw' })
    return isComplete(expression) ? expression.latex || null : null
  } catch {
    return null
  }
}

const converter = { latexToAst, astToLatex }
export type LatexConverter = typeof converter
Object.assign(globalThis, { folioLatex: converter })
