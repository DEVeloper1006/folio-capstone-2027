/**
 * Parse bounded scalar expressions with math.js and sample them for Plotly. Contains page-owned graph settings, parameter discovery, and explicit/implicit plotting without executing user JavaScript.
 *
 * @file
 */
import { isConstantNode, isFunctionNode, isOperatorNode, isParenthesisNode, isSymbolNode, parse } from 'mathjs'
import type { MathNode } from 'mathjs'
import type { Data, Layout } from 'plotly.js'

/** Preserve the rendered image, pixel aspect ratio, and Plotly axes/camera used to create it. */
export interface GraphSnapshot {
  image: string
  width: number
  height: number
  layout: Pick<Partial<Layout>, 'xaxis' | 'yaxis' | 'scene'>
}

export type GraphDimension = '2d' | '3d'
export interface GraphExpression {
  id: string
  source: string
  visible: boolean
}
export interface GraphParameter {
  value: number
  min: number
  max: number
  step: number
}
export interface GraphDomain {
  xmin: number
  xmax: number
  ymin: number
  ymax: number
}
export interface GraphDocument {
  dimension: GraphDimension
  expressions: Record<GraphDimension, GraphExpression[]>
  parameters: Record<string, GraphParameter>
  domain: GraphDomain
}
export const graphColors = ['#4864bf', '#bd4747', '#198265', '#9654b3', '#bb701b', '#26819b']
const functions = new Set(['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh', 'sqrt', 'abs', 'exp', 'log', 'log10', 'floor', 'ceil', 'round', 'min', 'max', 'sign'])

/** Create an empty worksheet without touching any notebook cells. */
export function createGraphDocument(): GraphDocument {
  return { dimension: '2d', expressions: { '2d': [], '3d': [] }, parameters: {}, domain: { xmin: -10, xmax: 10, ymin: -10, ymax: 10 } }
}

/** Start a discovered scalar at one with a modest editable slider range. */
export function graphParameter(graph: GraphDocument, name: string): GraphParameter {
  return graph.parameters[name] ?? { value: 1, min: -5, max: 5, step: 0.1 }
}

/** Require finite, ordered plotting bounds before allocating a sample grid. */
export function validGraphDomain(domain: GraphDomain) {
  return Object.values(domain).every(isBound) && domain.xmin < domain.xmax && domain.ymin < domain.ymax
}

/** Bound coordinates to a useful numeric range, avoiding overflow while sampling. */
function isBound(value: number) {
  return Number.isFinite(value) && Math.abs(value) <= 1e6
}

/** Require a finite scalar within its ordered range and a positive slider increment. */
export function validGraphParameter(parameter: GraphParameter) {
  return Object.values(parameter).every(isBound) && parameter.min < parameter.max && parameter.step > 0 && parameter.step <= parameter.max - parameter.min && parameter.value >= parameter.min && parameter.value <= parameter.max
}

/** Compile one equation, rejecting assignments, accessors, arrays, scripting, and unbounded operations. */
export function compileGraphExpression(source: string, dimension: GraphDimension) {
  if (!source.trim() || source.length > 300) throw new Error('Enter an expression of at most 300 characters.')
  const sides = source.split('=')
  let expression = source
  let implicit = false
  if (sides.length === 2 && sides.every(nonempty)) {
    if (sides[0].trim() === (dimension === '2d' ? 'y' : 'z')) expression = sides[1]
    else if (dimension === '2d') {
      expression = `(${sides[0]})-(${sides[1]})`
      implicit = true
    } else throw new Error('Use z = f(x, y) for a 3D surface.')
  } else if (sides.length !== 1) throw new Error('Use one equation, with an expression on each side.')
  const root = parse(expression)
  const parameters = new Set<string>()
  let count = 0
  /** Accept only numeric arithmetic and an explicit list of scalar functions. */
  function inspect(node: MathNode) {
    if (++count > 100) throw new Error('Simplify this expression to at most 100 terms and operations.')
    if (isConstantNode(node) && typeof node.value === 'number' && Number.isFinite(node.value)) return
    if (isParenthesisNode(node)) return
    if (isOperatorNode(node) && ['+', '-', '*', '/', '^', '%'].includes(node.op)) return
    if (isFunctionNode(node) && isSymbolNode(node.fn) && functions.has(node.fn.name) && node.args.length >= 1 && node.args.length <= 2) return
    if (isSymbolNode(node)) {
      if (functions.has(node.name) || ['pi', 'e', 'x'].includes(node.name)) return
      if (node.name === 'y' && (implicit || dimension === '3d')) return
      if (['y', 'z'].includes(node.name)) throw new Error(dimension === '2d' ? 'Use y = f(x), or an implicit equation such as x^2 + y^2 = 4.' : 'The surface expression may use x and y, not z.')
      if (!/^[a-z][a-z0-9_]{0,15}$/.test(node.name)) throw new Error('Use lowercase parameter names, such as a or radius.')
      parameters.add(node.name)
      if (parameters.size > 8) throw new Error('Use at most eight parameters per expression.')
      return
    }
    throw new Error('Only scalar arithmetic and supported math functions are allowed.')
  }
  root.traverse(inspect)
  const compiled = root.compile()
  /** Return a real finite coordinate, leaving undefined or complex regions as gaps. */
  function evaluate(scope: Record<string, number>): number | null {
    try {
      const value: unknown = compiled.evaluate(scope)
      return typeof value === 'number' && Number.isFinite(value) ? value : null
    } catch {
      return null
    }
  }
  return { implicit, parameters: [...parameters].sort(), evaluate }
}

/** Reject an empty side of an equation without silently repairing it. */
function nonempty(value: string) {
  return value.trim().length > 0
}

/** Produce an inclusive, bounded sampling axis. */
function axis(min: number, max: number, segments: number) {
  const values: number[] = []
  for (let index = 0; index <= segments; index++) values.push(min + ((max - min) * index) / segments)
  return values
}

/** Prepare independent traces and per-expression errors; one invalid equation does not hide valid neighbors. */
export function sampleGraph(graph: GraphDocument) {
  const traces: Data[] = []
  const errors: Record<string, string> = {}
  const names = new Set<string>()
  const { xmin, xmax, ymin, ymax } = graph.domain
  if (!validGraphDomain(graph.domain)) throw new Error('Plot bounds must be finite and increasing.')
  const expressions = graph.expressions[graph.dimension]
  for (const [index, row] of expressions.entries()) {
    if (!row.source.trim()) continue
    try {
      const formula = compileGraphExpression(row.source, graph.dimension)
      const scope: Record<string, number> = {}
      for (const name of formula.parameters) {
        names.add(name)
        const parameter = graphParameter(graph, name)
        if (!validGraphParameter(parameter)) throw new Error(`Check the slider range for ${name}.`)
        scope[name] = parameter.value
      }
      if (!row.visible) continue
      const color = graphColors[index % graphColors.length]
      if (graph.dimension === '2d' && !formula.implicit) {
        const x = axis(xmin, xmax, 1000)
        const y: (number | null)[] = []
        for (const coordinate of x) y.push(formula.evaluate({ ...scope, x: coordinate }))
        // shortcut: finite samples can miss narrow features; use adaptive sampling if precision becomes a requirement.
        for (let i = 1; i < x.length; i++) {
          const left = y[i - 1],
            right = y[i]
          const middle = formula.evaluate({ ...scope, x: (x[i - 1] + x[i]) / 2 })
          if (middle === null || (left !== null && right !== null && Math.abs(middle - (left + right) / 2) > ymax - ymin)) y[i] = null
        }
        if (!y.some(isReal)) throw new Error('No real values in this x range.')
        traces.push({ type: 'scatter', mode: 'lines', x, y, name: row.source, line: { color, width: 2.5 }, connectgaps: false })
      } else {
        const x = axis(xmin, xmax, graph.dimension === '3d' ? 64 : 120)
        const y = axis(ymin, ymax, graph.dimension === '3d' ? 64 : 120)
        const z: (number | null)[][] = []
        let finite = 0
        for (const yValue of y) {
          const rowValues: (number | null)[] = []
          for (const xValue of x) {
            const value = formula.evaluate({ ...scope, x: xValue, y: yValue })
            rowValues.push(value)
            if (value !== null) finite++
          }
          z.push(rowValues)
        }
        if (!finite) throw new Error('No real values in this domain.')
        if (graph.dimension === '3d')
          traces.push({
            type: 'surface',
            x,
            y,
            z,
            name: row.source,
            showscale: false,
            colorscale: [
              [0, color],
              [1, '#e5e9f2'],
            ],
            opacity: 0.88,
            connectgaps: false,
          })
        else
          traces.push({
            type: 'contour',
            x,
            y,
            z,
            name: row.source,
            showscale: false,
            autocontour: false,
            contours: { start: 0, end: 0, size: 1, coloring: 'lines' },
            colorscale: [
              [0, color],
              [1, color],
            ],
            line: { width: 2.5 },
            connectgaps: false,
          })
      }
    } catch (error) {
      errors[row.id] = error instanceof Error ? error.message : 'Unable to plot this expression.'
    }
  }
  return { traces, errors, parameters: [...names].sort() }
}

/** Recognize sampled coordinates without treating a domain gap as zero. */
function isReal(value: number | null) {
  return value !== null
}
