/**
 * Mount the CSP-compatible Plotly bundle in the browser. Serialize updates, retain camera/zoom during slider edits, capture the displayed view with its image, and release WebGL resources when leaving the graph.
 *
 * @file
 */
import { useEffect, useImperativeHandle, useRef, useState } from 'react'
import type { Ref } from 'react'
import type { Data, Layout, PlotlyHTMLElement, Camera } from 'plotly.js'
import type { GraphDimension, GraphDomain, GraphSnapshot } from './graph-model'

/** Export only a fully rendered plot, including its current pan, zoom, and camera. */
export interface GraphPlotController {
  capture: () => Promise<GraphSnapshot>
}

/** Read a finite camera vector from Plotly's runtime boundary. */
function cameraPoint(value: unknown) {
  if (!value || typeof value !== 'object' || !('x' in value) || !('y' in value) || !('z' in value) || typeof value.x !== 'number' || typeof value.y !== 'number' || typeof value.z !== 'number' || ![value.x, value.y, value.z].every(Number.isFinite))
    throw new Error('The graph camera could not be captured.')
  return { x: value.x, y: value.y, z: value.z }
}

/** Read the displayed WebGL camera: Plotly's public layout can lag behind the last scroll frame. Reject an incompatible renderer rather than save a different view. */
function renderedCamera(element: PlotlyHTMLElement): Camera & { projection: { type: 'perspective' | 'orthographic' } } {
  if (!('_fullLayout' in element) || !element._fullLayout || typeof element._fullLayout !== 'object' || !('scene' in element._fullLayout)) throw new Error('The graph scene is not ready for capture.')
  const scene = element._fullLayout.scene
  if (!scene || typeof scene !== 'object' || !('_scene' in scene) || !scene._scene || typeof scene._scene !== 'object' || !('getCamera' in scene._scene) || typeof scene._scene.getCamera !== 'function') throw new Error('This graph renderer does not expose its displayed camera.')
  const camera: unknown = scene._scene.getCamera()
  if (!camera || typeof camera !== 'object' || !('eye' in camera) || !('up' in camera) || !('center' in camera) || !('projection' in camera)) throw new Error('The displayed camera is incomplete.')
  const projection = camera.projection
  if (!projection || typeof projection !== 'object' || !('type' in projection) || (projection.type !== 'perspective' && projection.type !== 'orthographic')) throw new Error('The camera projection is unsupported.')
  return { eye: cameraPoint(camera.eye), up: cameraPoint(camera.up), center: cameraPoint(camera.center), projection: { type: projection.type } }
}

/** Render sampled traces using Plotly's native zoom, pan, hover, and orbit controls. */
export function GraphPlot({ traces, dimension, domain, revision, snapshot, controllerRef }: { traces: Data[]; dimension: GraphDimension; domain: GraphDomain; revision: number; snapshot?: GraphSnapshot; controllerRef: Ref<GraphPlotController> }) {
  const host = useRef<HTMLDivElement>(null)
  const plot = useRef<PlotlyHTMLElement | null>(null)
  const renderedTraces = useRef<Data[] | null>(null)
  const queue = useRef(Promise.resolve())
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  /** Capture the current renderer rather than reconstructing an image from the equations. */
  function bindController(): GraphPlotController {
    /** Wait for drawing, export at the displayed aspect ratio, and reject an obsolete export. */
    async function capture() {
      await queue.current
      const element = plot.current
      if (!element || renderedTraces.current !== traces || error) throw new Error('Wait for the graph to finish rendering before inserting it.')
      const width = element.clientWidth
      const height = element.clientHeight
      const layout = structuredClone({ xaxis: element.layout.xaxis, yaxis: element.layout.yaxis, scene: element.layout.scene })
      if (dimension === '3d') layout.scene = { ...layout.scene, camera: renderedCamera(element) }
      const { default: Plotly } = await import('plotly.js-strict-dist-min')
      const image = await Plotly.toImage({ data: structuredClone(element.data), layout: { ...element.layout, ...layout } }, { format: 'png', width, height, scale: 2 })
      if (plot.current !== element || renderedTraces.current !== traces) throw new Error('The graph changed during capture. Insert the view again.')
      return { image, width, height, layout }
    }
    return { capture }
  }
  useImperativeHandle(controllerRef, bindController)
  /** Apply the latest samples without resetting the current camera during parameter changes. */
  function renderPlot() {
    const element = host.current
    if (!element) return
    const pending = { cancelled: false }
    /** Read cancellation again after asynchronous rendering can yield to cleanup. */
    function isCancelled() {
      return pending.cancelled
    }
    /** Run one Plotly update after the previous update has settled. */
    async function draw() {
      if (!element) return
      try {
        const { default: Plotly } = await import('plotly.js-strict-dist-min')
        if (isCancelled()) return
        const style = getComputedStyle(element)
        const background = style.getPropertyValue('--canvas').trim() || '#fff'
        const ink = style.getPropertyValue('--ink').trim() || '#252525'
        const grid = style.getPropertyValue('--line').trim() || '#e5e5e5'
        const viewKey = `${dimension}:${JSON.stringify(domain)}:${revision}`
        const layout: Partial<Layout> = {
          autosize: true,
          paper_bgcolor: background,
          plot_bgcolor: background,
          font: { color: ink },
          margin: { l: 48, r: 24, t: 24, b: 48 },
          showlegend: false,
          dragmode: dimension === '2d' ? 'pan' : 'orbit',
          uirevision: viewKey,
          xaxis: { title: { text: 'x' }, range: [domain.xmin, domain.xmax], gridcolor: grid, zerolinecolor: ink, constrain: 'domain' },
          yaxis: { title: { text: 'y' }, range: [domain.ymin, domain.ymax], gridcolor: grid, zerolinecolor: ink, scaleanchor: 'x', scaleratio: 1, constrain: 'domain' },
          scene: { aspectmode: 'cube', xaxis: { title: { text: 'x' }, range: [domain.xmin, domain.xmax] }, yaxis: { title: { text: 'y' }, range: [domain.ymin, domain.ymax] }, zaxis: { title: { text: 'z' } } },
          ...(revision === 0 && snapshot ? structuredClone(snapshot.layout) : undefined),
        }
        plot.current = await Plotly.react(element, traces, layout, { responsive: true, scrollZoom: true, displaylogo: false, displayModeBar: true, modeBarButtonsToRemove: ['sendChartToCloud'] })
        if (!isCancelled()) {
          renderedTraces.current = traces
          setError('')
          setLoading(false)
        }
      } catch (cause) {
        if (!isCancelled()) {
          setError(cause instanceof Error ? cause.message : 'Graph rendering failed.')
          setLoading(false)
        }
      }
    }
    queue.current = queue.current.then(draw)
    /** Skip obsolete samples queued by rapid typing or slider movement. */
    function cancelDraw() {
      pending.cancelled = true
    }
    return cancelDraw
  }
  useEffect(renderPlot, [traces, dimension, domain, revision, snapshot])
  /** Resize for sidebar changes and clean up only after pending drawing has finished. */
  function observeSize() {
    const element = host.current
    if (!element) return
    let disposed = false
    /** Resize Plotly after a container change without rebuilding its data. */
    async function resize() {
      if (!element) return
      const { default: Plotly } = await import('plotly.js-strict-dist-min')
      if (!disposed && element.classList.contains('js-plotly-plot')) await Plotly.Plots.resize(element)
    }
    const observer = new ResizeObserver(resize)
    observer.observe(element)
    /** Release observers and the plot's graphics context after the last update. */
    function cleanup() {
      disposed = true
      plot.current = null
      observer.disconnect()
      /** Dispose the detached plot after rendering has settled. */
      async function purge() {
        if (!element) return
        const { default: Plotly } = await import('plotly.js-strict-dist-min')
        Plotly.purge(element)
      }
      void queue.current.then(purge)
    }
    return cleanup
  }
  useEffect(observeSize, [])
  return (
    <div className="graph-figure">
      <div ref={host} className="graph-canvas" style={snapshot ? { aspectRatio: `${snapshot.width} / ${snapshot.height}`, height: 'auto' } : undefined} aria-label={`Interactive ${dimension.toUpperCase()} graph`} />
      {loading && <p role="status">Loading graph renderer…</p>}
      {error && <p role="alert">{error} Try reopening Graph; 3D requires WebGL.</p>}
    </div>
  )
}
