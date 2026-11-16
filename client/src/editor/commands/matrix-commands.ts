/**
 * Generate editable matrix templates from dimensions and optional sparse entries. Contains validation shared by the builder and matrix-capable fields.
 *
 * @file
 */

import katex from 'katex'
import { previewMacros } from '../mathlive/mathfield-macros'

/** Keep expanded matrices small enough to navigate as notebook formulas. Larger symbolic matrices use ellipses. */
export const maximumMatrixSize = 20
export type MatrixBrackets = 'pmatrix' | 'bmatrix' | 'vmatrix' | 'matrix'

/** Select the expanded matrix shape and the zero-filled default for sparse input. Sparse coordinates are entered as one-based row, column, LaTeX lines. */
export interface MatrixOptions {
  rows: number
  columns: number
  brackets: MatrixBrackets
  sparse: boolean
  entries: string
}

/** Build a LaTeX template or return the first input error. Empty dense entries remain editable MathLive placeholders. */
export function matrixTemplate(options: MatrixOptions): { latex: string; error?: never } | { error: string; latex?: never } {
  const { rows, columns, brackets, sparse, entries } = options
  if (!Number.isInteger(rows) || !Number.isInteger(columns) || rows < 1 || columns < 1 || rows > maximumMatrixSize || columns > maximumMatrixSize) return { error: `Rows and columns must be whole numbers from 1 to ${maximumMatrixSize}.` }
  const values = new Map<string, string>()
  for (const [index, line] of (sparse ? entries.split('\n') : []).entries()) {
    if (!line.trim()) continue
    const match = /^\s*(\d+)\s*,\s*(\d+)\s*,\s*(.+?)\s*$/.exec(line)
    if (!match) return { error: `Line ${index + 1}: use row, column, LaTeX.` }
    const row = Number(match[1]),
      column = Number(match[2]),
      latex = match[3]
    if (row < 1 || row > rows || column < 1 || column > columns) return { error: `Line ${index + 1}: position is outside the matrix.` }
    if (/[&\n]/.test(latex) || /\\\\|\\(?:begin|end)\b/.test(latex)) return { error: `Line ${index + 1}: enter one cell expression.` }
    try {
      katex.renderToString(latex, { macros: { ...previewMacros }, throwOnError: true, strict: 'ignore' })
    } catch {
      return { error: `Line ${index + 1}: the cell contains invalid LaTeX.` }
    }
    const key = `${row},${column}`
    if (values.has(key)) return { error: `Line ${index + 1}: position ${key} is already entered.` }
    values.set(key, latex)
  }
  /** Fill one row with placeholders, or sparse entries and zeros. */
  function matrixRow(_unused: unknown, row: number) {
    /** Look up one explicitly entered position. */
    function entry(_cellValue: unknown, column: number) {
      return values.get(`${row + 1},${column + 1}`) ?? (sparse ? '0' : '#?')
    }
    return Array.from({ length: columns }, entry).join(' & ')
  }
  return { latex: `\\begin{${brackets}}${Array.from({ length: rows }, matrixRow).join(' \\\\ ')}\\end{${brackets}}` }
}
