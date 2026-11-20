/**
 * Edit a page's scratch graph or a local draft of an inserted graph. Capture the renderer's image and view into an ordered notebook cell only when the user chooses Insert or Update view.
 *
 * @file
 */
import { useDeferredValue, useMemo, useRef, useState } from 'react'
import { ChartLine, Plus, RotateCcw, X } from 'lucide-react'
import type { ChangeEvent, FormEvent } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Button, SegmentedControl, TextField } from '#/component-library'
import { notebookCommands, usePageSelection } from '#/notebook/use-page-state'
import type { Page } from '#/notebook/page'
import { createCellId } from '#/notebook/notebook-cells'
import type { GraphNotebookCell, NotebookCell } from '#/notebook/notebook-cells'
import { createGraphDocument, graphColors, graphParameter, sampleGraph, validGraphDomain, validGraphParameter } from './graph-model'
import type { GraphDimension, GraphDocument, GraphDomain, GraphExpression, GraphParameter } from './graph-model'
import { GraphPlot } from './graph-plot'
import type { GraphPlotController } from './graph-plot'
import './graph.css'

/** Host a persistent graph worksheet for the currently selected page. */
export function GraphWorkspace({ pageId, cellId, onClose }: { pageId: string; cellId?: string; onClose: () => void }) {
  /** Select the target cell independently from the page's scratch graph. */
  function selectGraph(page: Page) {
    return cellId ? page.cells.find(matchesCell) : page.graph
  }
  /** Locate only the explicitly requested notebook cell. */
  function matchesCell(cell: NotebookCell) {
    return cell.cellId === cellId
  }
  const saved = usePageSelection(pageId, selectGraph)
  const savedCell = saved && 'kind' in saved && saved.kind === 'graph' ? saved : undefined
  const [cellDraft, setCellDraft] = useState(savedCell?.graph)
  const [empty] = useState(createGraphDocument)
  const graph = cellDraft ?? (saved && 'dimension' in saved ? saved : empty)
  const { updatePage } = notebookCommands(useQueryClient())
  const plotRef = useRef<GraphPlotController>(null)
  const [capturing, setCapturing] = useState(false)
  const deferred = useDeferredValue(graph)
  const [saveError, setSaveError] = useState('')
  const [revision, setRevision] = useState(0)
  const [draft, setDraft] = useState('')
  const draftRef = useRef<HTMLInputElement>(null)
  /** Sample only when the deferred graph changes, not on unrelated UI state updates. */
  function prepare() {
    return sampleGraph(deferred)
  }
  const result = useMemo(prepare, [deferred])
  const rows = graph.expressions[graph.dimension]
  /** Persist graphs through the notebook's existing page writer, preserving all cells and metadata. */
  function changeGraph(next: GraphDocument) {
    if (cellId) {
      setCellDraft(next)
      return true
    }
    /** Replace only the graph field on the latest page. */
    function replaceGraph(page: Page) {
      return { ...page, graph: next }
    }
    try {
      updatePage(pageId, replaceGraph)
      setSaveError('')
      return true
    } catch {
      setSaveError('Unable to save graph changes. Free local storage before continuing; the previous graph is unchanged.')
      return false
    }
  }
  /** Switch dimensionality while retaining a separate expression list for each space. */
  function changeDimension(dimension: GraphDimension) {
    setRevision(revision + 1)
    changeGraph({ ...graph, dimension })
  }
  /** Replace the current dimension's expression list without touching the other list. */
  function changeRows(next: GraphExpression[]) {
    return changeGraph({ ...graph, expressions: { ...graph.expressions, [graph.dimension]: next } })
  }
  /** Keep the next equation separate until the user chooses Plot or presses Enter. */
  function editDraft(event: ChangeEvent<HTMLInputElement>) {
    setDraft(event.target.value)
  }
  /** Add the typed equation and leave focus ready for the next, up to six traces per space. */
  function addExpression(event: FormEvent) {
    event.preventDefault()
    if (!draft.trim() || rows.length >= 6) return
    if (!changeRows([...rows, { id: crypto.randomUUID(), source: draft.trim(), visible: true }])) return
    setDraft('')
    draftRef.current?.focus()
  }
  /** Restore the declared domain and initial 3D camera. */
  function resetView() {
    setRevision(revision + 1)
  }
  /** Save ordered bounds after the domain form validates them. */
  function changeDomain(domain: GraphDomain) {
    setRevision(revision + 1)
    changeGraph({ ...graph, domain })
  }
  /** Atomically save the captured image and editable source; keep the previous cell when export or storage fails. */
  async function insertView() {
    if (capturing || !plotRef.current || graph !== deferred) return
    setCapturing(true)
    setSaveError('')
    try {
      const snapshot = await plotRef.current.capture()
      const inserted: GraphNotebookCell = { cellId: cellId ?? createCellId(), kind: 'graph', graph: structuredClone(graph), snapshot }
      /** Replace an existing graph in place or append a new graph to the document. */
      function saveView(page: Page): Page {
        if (!cellId) return { ...page, cells: [...page.cells, inserted] }
        if (!page.cells.some(matchesCell)) throw new Error('The graph cell was removed. Close this panel and insert a new graph.')
        /** Leave every other cell untouched. */
        function replace(cell: NotebookCell) {
          return cell.cellId === cellId ? { ...cell, ...inserted } : cell
        }
        return { ...page, cells: page.cells.map(replace) }
      }
      updatePage(pageId, saveView)
      onClose()
      /** Reveal and focus the saved figure after the panel has closed. */
      function reveal() {
        const figure = document.querySelector<HTMLElement>(`[data-cell-id="${CSS.escape(inserted.cellId)}"]`)
        figure?.scrollIntoView({ block: 'nearest' })
        figure?.focus({ preventScroll: true })
      }
      requestAnimationFrame(reveal)
    } catch (cause) {
      setSaveError(cause instanceof Error ? cause.message : 'Could not insert this view. Your document is unchanged.')
    } finally {
      setCapturing(false)
    }
  }
  /** Render one labeled expression with local errors and visibility controls. */
  function renderExpression(row: GraphExpression, index: number) {
    /** Replace this expression without changing neighboring traces. */
    function changeSource(event: ChangeEvent<HTMLInputElement>) {
      const source = event.target.value
      /** Preserve every other row. */
      function replace(item: GraphExpression) {
        return item.id === row.id ? { ...item, source } : item
      }
      changeRows(rows.map(replace))
    }
    /** Hide a trace while retaining its equation and parameters. */
    function changeVisibility() {
      /** Toggle only this row's visibility. */
      function toggle(item: GraphExpression) {
        return item.id === row.id ? { ...item, visible: !item.visible } : item
      }
      changeRows(rows.map(toggle))
    }
    /** Remove only the chosen graph expression. */
    function remove() {
      /** Keep the remaining expressions in order. */
      function keep(item: GraphExpression) {
        return item.id !== row.id
      }
      changeRows(rows.filter(keep))
    }
    return (
      <div className="graph-expression" key={row.id} style={{ borderInlineStartColor: graphColors[index % graphColors.length] }}>
        <TextField label={`Expression ${index + 1}`} value={row.source} maxLength={300} onChange={changeSource} placeholder={graph.dimension === '2d' ? 'y = a*sin(x)' : 'z = a*sin(x)*cos(y)'} autoComplete="off" spellCheck={false} />
        <div className="graph-row-actions">
          <label>
            <input type="checkbox" checked={row.visible} onChange={changeVisibility} aria-label={`Show expression ${index + 1}`} /> Show
          </label>
          <Button variant="quiet" onClick={remove} aria-label={`Remove expression ${index + 1}`}>
            Remove
          </Button>
        </div>
        {result.errors[row.id] && (
          <p className="graph-error" role="alert">
            {result.errors[row.id]}
          </p>
        )}
      </div>
    )
  }
  /** Render one automatically discovered parameter with its saved limits. */
  function renderParameter(name: string) {
    /** Persist a scalar or range change without replacing other parameters. */
    function change(parameter: GraphParameter) {
      changeGraph({ ...graph, parameters: { ...graph.parameters, [name]: parameter } })
    }
    return <ParameterControl key={name} name={name} parameter={graphParameter(graph, name)} onChange={change} />
  }
  return (
    <aside className="graph-workspace" aria-label={cellId ? 'Edit graph' : 'Graph panel'} aria-busy={capturing} inert={capturing}>
      <header className="graph-header">
        <div>
          <h2>
            <ChartLine size={17} aria-hidden="true" />
            Graph
          </h2>
        </div>
        <SegmentedControl<GraphDimension>
          label="Graph dimension"
          value={graph.dimension}
          onValueChange={changeDimension}
          options={[
            { value: '2d', label: '2D' },
            { value: '3d', label: '3D' },
          ]}
        />
        <Button variant="quiet" onClick={resetView} title="Reset view">
          <RotateCcw size={14} aria-hidden="true" />
          <span>Reset</span>
        </Button>
        <Button variant="quiet" onClick={onClose} disabled={capturing} aria-label="Close graph panel">
          <X size={16} aria-hidden="true" />
        </Button>
      </header>
      <div className="graph-insert">
        <Button onClick={insertView} disabled={capturing || graph !== deferred || !result.traces.length || !!Object.keys(result.errors).length}>
          {capturing ? 'Capturing…' : cellId ? 'Update view' : 'Insert view'}
        </Button>
        <span>{cellId ? 'Changes apply when you update the view.' : 'Place this view in your document.'}</span>
      </div>
      {saveError && (
        <p role="alert" className="graph-error">
          {saveError}
        </p>
      )}
      <div className="graph-body">
        <aside className="graph-controls" aria-label="Graph controls">
          {rows.map(renderExpression)}
          <form className="graph-compose" onSubmit={addExpression}>
            <label htmlFor={`graph-draft-${pageId}`}>{rows.length ? 'Add another equation' : 'Your first equation'}</label>
            <div>
              <input id={`graph-draft-${pageId}`} ref={draftRef} value={draft} onChange={editDraft} maxLength={300} placeholder={graph.dimension === '2d' ? 'y = a*sin(x)' : 'z = a*sin(x)*cos(y)'} autoComplete="off" spellCheck={false} disabled={rows.length >= 6} />
              <Button type="submit" disabled={!draft.trim() || rows.length >= 6}>
                <Plus size={14} aria-hidden="true" />
                Plot
              </Button>
            </div>
            <p>{rows.length >= 6 ? 'Six equations per view. Edit or remove one to add another.' : 'Press Enter to plot. Add a letter like a to get a slider.'}</p>
          </form>
          {result.parameters.length > 0 && (
            <section aria-label="Parameters">
              <h3>Sliders</h3>
              {result.parameters.map(renderParameter)}
            </section>
          )}
          <details className="graph-settings">
            <summary>Plot range</summary>
            <DomainControl domain={graph.domain} onChange={changeDomain} />
          </details>
          <details className="graph-help">
            <summary>How to write equations</summary>
            <p>{graph.dimension === '2d' ? 'Curves: y = f(x). Circles: x^2 + y^2 = r^2.' : 'Surfaces: z = f(x, y).'} Use ^ for powers and radians for angles.</p>
            <p>
              Arithmetic: + − * / ^ %. Functions: sin, cos, tan, asin, acos, atan, sinh, cosh, tanh, sqrt, abs, exp, log, log10, floor, ceil, round, min, max, sign. Constants: pi, e. No assignments, code, lists, inequalities, or 3D implicit solids. Plots are numerical samples, not proofs; very
              narrow features may be missed.
            </p>
          </details>
        </aside>
        <section className="graph-display" aria-label="Plot">
          {rows.length ? (
            <GraphPlot traces={result.traces} dimension={deferred.dimension} domain={deferred.domain} revision={revision} snapshot={savedCell?.snapshot} controllerRef={plotRef} />
          ) : (
            <div className="graph-empty">
              <ChartLine size={36} strokeWidth={1.2} aria-hidden="true" />
              <h3>See your idea take shape</h3>
              <p>
                Enter an equation, then move its sliders.
                <br />
                Your graph belongs to this page.
              </p>
            </div>
          )}
          <p className="graph-caption" role="status">
            {graph !== deferred ? 'Updating…' : `${result.traces.length} plotted`} · {graph.dimension === '3d' ? 'Drag to rotate · Scroll to zoom' : 'Drag to pan · Scroll to zoom'}
          </p>
        </section>
      </div>
    </aside>
  )
}

/** Edit slider limits locally and persist only valid ranges; slider movement updates the graph immediately. */
function ParameterControl({ name, parameter, onChange }: { name: string; parameter: GraphParameter; onChange: (parameter: GraphParameter) => void }) {
  const [min, setMin] = useState(String(parameter.min)),
    [max, setMax] = useState(String(parameter.max)),
    [step, setStep] = useState(String(parameter.step))
  const [error, setError] = useState('')
  /** Move the scalar inside the current limits. */
  function move(event: ChangeEvent<HTMLInputElement>) {
    const next = { ...parameter, value: event.target.valueAsNumber }
    if (validGraphParameter(next)) onChange(next)
  }
  /** Retain incomplete minimum edits until submission. */
  function editMin(event: ChangeEvent<HTMLInputElement>) {
    setMin(event.target.value)
  }
  /** Retain incomplete maximum edits until submission. */
  function editMax(event: ChangeEvent<HTMLInputElement>) {
    setMax(event.target.value)
  }
  /** Retain incomplete step edits until submission. */
  function editStep(event: ChangeEvent<HTMLInputElement>) {
    setStep(event.target.value)
  }
  /** Apply limits and let the native range control align the value to its new step grid. */
  function apply(event: FormEvent) {
    event.preventDefault()
    const next = { min: min.trim() ? Number(min) : NaN, max: max.trim() ? Number(max) : NaN, step: step.trim() ? Number(step) : NaN, value: Math.min(Number(max), Math.max(Number(min), parameter.value)) }
    if (!validGraphParameter(next)) {
      setError('Use increasing bounds and a positive step no larger than the range.')
      return
    }
    const slider = document.createElement('input')
    slider.type = 'range'
    slider.min = String(next.min)
    slider.max = String(next.max)
    slider.step = String(next.step)
    slider.value = String(next.value)
    setError('')
    onChange({ ...next, value: slider.valueAsNumber })
  }
  return (
    <form className="graph-parameter" onSubmit={apply} aria-label={`Parameter ${name}`}>
      <div className="graph-parameter-value">
        <strong>{name}</strong>
        <TextField label={`${name} value`} type="number" value={parameter.value} min={parameter.min} max={parameter.max} step={parameter.step} onChange={move} />
      </div>
      <input aria-label={`${name} slider`} type="range" min={parameter.min} max={parameter.max} step={parameter.step} value={parameter.value} onChange={move} />
      <details className="graph-slider-settings">
        <summary>Slider settings</summary>
        <div className="graph-range-fields">
          <TextField label={`${name} min`} type="number" value={min} onChange={editMin} step="any" />
          <TextField label={`${name} max`} type="number" value={max} onChange={editMax} step="any" />
          <TextField label={`${name} step`} type="number" value={step} onChange={editStep} step="any" />
        </div>
        <Button type="submit" variant="quiet">
          Apply slider settings
        </Button>
      </details>
      {error && (
        <p role="alert" className="graph-error">
          {error}
        </p>
      )}
    </form>
  )
}

/** Let domain text remain incomplete while editing; submit only finite increasing axes. */
function DomainControl({ domain, onChange }: { domain: GraphDomain; onChange: (domain: GraphDomain) => void }) {
  const [draft, setDraft] = useState({ xmin: String(domain.xmin), xmax: String(domain.xmax), ymin: String(domain.ymin), ymax: String(domain.ymax) })
  const [error, setError] = useState('')
  /** Validate the whole domain before replacing the sampled region. */
  function apply(event: FormEvent) {
    event.preventDefault()
    const next = { xmin: Number(draft.xmin), xmax: Number(draft.xmax), ymin: Number(draft.ymin), ymax: Number(draft.ymax) }
    if (Object.values(draft).includes('') || !validGraphDomain(next)) {
      setError('Enter finite increasing bounds within ±1,000,000.')
      return
    }
    setError('')
    onChange(next)
  }
  /** Render a labeled bound and retain its draft independently. */
  function field(key: keyof GraphDomain) {
    /** Store the bound without coercing partial input. */
    function change(event: ChangeEvent<HTMLInputElement>) {
      setDraft({ ...draft, [key]: event.target.value })
    }
    return <TextField key={key} label={key.replace('min', ' min').replace('max', ' max')} type="number" value={draft[key]} step="any" onChange={change} />
  }
  return (
    <form className="graph-domain" onSubmit={apply}>
      <p className="graph-help">Equations are sampled within these bounds. Widen them to explore beyond the current plot.</p>
      <div className="graph-domain-fields">
        {field('xmin')}
        {field('xmax')}
        {field('ymin')}
        {field('ymax')}
      </div>
      <Button type="submit">Update plot range</Button>
      {error && (
        <p role="alert" className="graph-error">
          {error}
        </p>
      )}
    </form>
  )
}
