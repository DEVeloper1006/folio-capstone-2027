/**
 * Configure a matrix with dimensions, delimiters and optional sparse coordinates. Reuses the notebook's shared form controls and renders the generated notation before insertion.
 *
 * @file
 */
import { useEffect, useRef, useState } from 'react'
import type { ChangeEvent, FormEvent, KeyboardEvent } from 'react'
import { Button } from './button'
import { TextField } from './text-field'
import { SegmentedControl } from './segmented-control'
import { InlineLatex } from './primitives/chat-math'
import { matrixTemplate, maximumMatrixSize } from '#/editor/commands/matrix-commands'
import type { MatrixBrackets } from '#/editor/commands/matrix-commands'

/** Edit a concrete matrix before handing its LaTeX to the same insertion path as other expressions. */
export function MatrixBuilder({ initialSparse = false, onInsert, onCancel }: { initialSparse?: boolean; onInsert: (latex: string) => void; onCancel: () => void }) {
  const [rows, setRows] = useState('3')
  const [columns, setColumns] = useState('3')
  const [brackets, setBrackets] = useState<MatrixBrackets>('pmatrix')
  const [fill, setFill] = useState(initialSparse ? 'sparse' : 'blank')
  const [entries, setEntries] = useState('')
  const firstField = useRef<HTMLDivElement>(null)
  const result = matrixTemplate({ rows: Number(rows), columns: Number(columns), brackets, sparse: fill === 'sparse', entries })
  /** Place keyboard focus in the dimension field when opened. */
  function focusRows() {
    firstField.current?.querySelector('input')?.focus()
  }
  useEffect(focusRows, [])
  /** Update the row count without coercing an incomplete field. */
  function changeRows(event: ChangeEvent<HTMLInputElement>) {
    setRows(event.target.value)
  }
  /** Update the column count independently, allowing rectangular matrices. */
  function changeColumns(event: ChangeEvent<HTMLInputElement>) {
    setColumns(event.target.value)
  }
  /** Store one-based nonzero coordinate entries. */
  function changeEntries(event: ChangeEvent<HTMLTextAreaElement>) {
    setEntries(event.target.value)
  }
  /** Insert only a valid matrix. The expression session restores the original cursor. */
  function submit(event: FormEvent) {
    event.preventDefault()
    if (result.latex !== undefined) onInsert(result.latex)
  }
  /** Return to expression results when Escape is pressed. */
  function handleKey(event: KeyboardEvent) {
    if (event.key !== 'Escape') return
    event.preventDefault()
    event.stopPropagation()
    onCancel()
  }
  return (
    <form className="matrix-builder" aria-label="Matrix builder" onSubmit={submit} onKeyDown={handleKey}>
      <div className="matrix-dimensions" ref={firstField}>
        <TextField label="Rows" type="number" min={1} max={maximumMatrixSize} step={1} value={rows} onChange={changeRows} />
        <TextField label="Columns" type="number" min={1} max={maximumMatrixSize} step={1} value={columns} onChange={changeColumns} />
      </div>
      <SegmentedControl<MatrixBrackets>
        label="Matrix brackets"
        value={brackets}
        onValueChange={setBrackets}
        options={[
          { value: 'pmatrix', label: '( )' },
          { value: 'bmatrix', label: '[ ]' },
          { value: 'vmatrix', label: '| |' },
          { value: 'matrix', label: 'None' },
        ]}
      />
      <SegmentedControl
        label="Matrix entries"
        value={fill}
        onValueChange={setFill}
        options={[
          { value: 'blank', label: 'Blank' },
          { value: 'sparse', label: 'Sparse' },
        ]}
      />
      {fill === 'sparse' && (
        <label className="ui-field">
          <span className="ui-field-label">Nonzero entries (row, column, LaTeX)</span>
          <textarea className="ui-field-input" aria-label="Nonzero entries" rows={4} value={entries} onChange={changeEntries} placeholder={'1, 1, a\n3, 2, \\frac{1}{2}'} />
        </label>
      )}
      {result.latex === undefined ? (
        <p role="alert">{result.error}</p>
      ) : (
        <div className="matrix-preview" aria-label="Matrix preview">
          <InlineLatex latex={result.latex.replaceAll('#?', String.raw`\placeholder{}`)} display />
        </div>
      )}
      <div className="matrix-actions">
        <Button type="button" variant="quiet" onClick={onCancel}>
          Back
        </Button>
        <Button type="submit" disabled={result.latex === undefined}>
          Insert matrix
        </Button>
      </div>
    </form>
  )
}
