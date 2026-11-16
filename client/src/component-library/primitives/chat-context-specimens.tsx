/**
 * Show drag-to-highlight math and cell selections that attach to chat, plus chat context pills with Base UI hover preview cards.
 *
 * Highlight paint is design-only: each paintable glyph region is its own box, so a selection can be disjoint, stepped, or taller than its neighbors.
 *
 * @file
 */

import { useLayoutEffect, useRef, useState } from 'react'
import type { PointerEvent as ReactPointerEvent } from 'react'
import katex from 'katex'
import type { TrustContext } from 'katex'
import { Menu } from '@base-ui/react/menu'
import { PreviewCard } from '@base-ui/react/preview-card'
import { AddToChatIcon, AssistantSparklesIcon, AttachContextIcon, CloseIcon, CopyIcon, FileAttachmentIcon, JumpToCellIcon, MarkdownIcon, MathIcon, PasteSnippetIcon, SubExpressionIcon, SymbolicComputeIcon, WebLinkIcon } from '#/component-library/icons/folio-icons.tsx'
import { ChatMarkdown, InlineLatex } from './chat-math.tsx'
import { IconTooltip } from './icon-tooltip.tsx'

/** Describe one item attached to the chat composer, along with the rich content shown in its hover preview card. */
export type ContextAttachment =
  | {
      id: string
      kind: 'math-cell'
      label: string
      meta: string
      latex: string
      note: string
    }
  | {
      id: string
      kind: 'sub-expression'
      cellLabel: string
      chipLatex: string
      beforeLatex: string
      selectedLatex: string
      afterLatex: string
      /** Glyph regions in highlight order. Present when the selection is one or more painted boxes rather than a single sliced span. */
      regions?: readonly string[]
      /** Full parent formula with `\htmlClass{hl-zone}` only around the regions that are highlighted. */
      previewLatex?: string
    }
  | {
      id: string
      kind: 'markdown-cell'
      label: string
      meta: string
      markdown: string
    }
  | {
      id: string
      kind: 'pasted-text'
      label: string
      meta: string
      snippet: string
    }
  | {
      id: string
      kind: 'web-link'
      label: string
      domain: string
      url: string
      excerpt: string
    }
  | {
      id: string
      kind: 'file'
      filename: string
      meta: string
      excerpt: string
    }

/** Default catalog of notebook, paste, link, and file attachments shown in the context gallery. */
export const sampleContextCatalog: readonly ContextAttachment[] = [
  {
    id: 'ctx-subexpr-reg',
    kind: 'sub-expression',
    cellLabel: 'Cell 4',
    chipLatex: '\\lambda \\|\\theta\\|_2^2',
    beforeLatex: '\\mathcal{L}(\\theta) = \\frac{1}{N}\\sum_{i=1}^{N}(y_i - f_\\theta(x_i))^2 + ',
    selectedLatex: '\\lambda \\|\\theta\\|_2^2',
    afterLatex: '',
  },
  {
    id: 'ctx-math-cell-3',
    kind: 'math-cell',
    label: 'Cell 3',
    meta: 'Math',
    latex: '\\Gamma(s) = \\int_0^\\infty x^{s-1} e^{-x}\\,dx, \\quad \\operatorname{Re}(s) > 0',
    note: 'Convergent improper integral defining the Gamma function.',
  },
  {
    id: 'ctx-md-cell-1',
    kind: 'markdown-cell',
    label: 'Cell 1',
    meta: 'Assumptions',
    markdown: 'Assume $X \\in \\mathbb{R}^{N \\times d}$ has full column rank and the regularization weight satisfies $\\lambda > 0$.',
  },
  {
    id: 'ctx-paste-log',
    kind: 'pasted-text',
    label: 'Pasted text',
    meta: '48 lines · 1.9 KB',
    snippet: `Traceback (most recent call last):\n  File "solve_ridge.py", line 27, in <module>\n    chol = np.linalg.cholesky(X.T @ X)\nnumpy.linalg.LinAlgError: Matrix is not positive definite\n# min eigenvalue: -1.42e-16 before adding 2 * lam * I`,
  },
  {
    id: 'ctx-link-arxiv',
    kind: 'web-link',
    label: 'arXiv:2402.0192',
    domain: 'arxiv.org · Theorem 3.1',
    url: 'https://arxiv.org/abs/2402.0192',
    excerpt: 'Adding $\\lambda \\|\\theta\\|_2^2$ shifts every eigenvalue of the Hessian by $2\\lambda$, bounding the condition number by $\\kappa \\le 1 + L / (2\\lambda)$.',
  },
  {
    id: 'ctx-file-pdf',
    kind: 'file',
    filename: 'problem-set-4.pdf',
    meta: 'PDF · p. 3 · 412 KB',
    excerpt: '**Problem 3(b).** Prove that $\\nabla^2 \\mathcal{L}(\\theta) = \\frac{2}{N}X^\\top X + 2\\lambda I$ is strictly positive definite for all $\\lambda > 0$.',
  },
]

/** Render the leading icon that identifies a context attachment's source kind. */
function renderAttachmentIcon(kind: ContextAttachment['kind']) {
  if (kind === 'math-cell') return <MathIcon />
  if (kind === 'sub-expression') return <SubExpressionIcon />
  if (kind === 'markdown-cell') return <MarkdownIcon />
  if (kind === 'pasted-text') return <PasteSnippetIcon />
  if (kind === 'web-link') return <WebLinkIcon />
  return <FileAttachmentIcon />
}

/** Render one highlighted glyph region as its own box inside a context pill. */
function renderChipRegion(latex: string, index: number) {
  return (
    <span key={`${index}-${latex}`} className="context-chip-region">
      <InlineLatex latex={latex} />
    </span>
  )
}

/** Render every highlighted region as a separate box so a disjoint selection is not drawn as one rectangle. */
function renderChipRegions(regions: readonly string[]) {
  const chips = []
  for (let index = 0; index < regions.length; index += 1) chips.push(renderChipRegion(regions[index], index))
  return chips
}

/** Render the visible title and secondary badge inside a context pill button. */
function renderAttachmentChipContent(attachment: ContextAttachment) {
  if (attachment.kind === 'sub-expression') {
    const regions = attachment.regions
    return (
      <>
        <SubExpressionIcon />
        {regions !== undefined && regions.length > 0 ? (
          renderChipRegions(regions)
        ) : (
          <span className="context-chip-math">
            <InlineLatex latex={attachment.chipLatex} />
          </span>
        )}
        <span className="context-chip-meta">{attachment.cellLabel}</span>
      </>
    )
  }
  if (attachment.kind === 'math-cell' || attachment.kind === 'markdown-cell' || attachment.kind === 'pasted-text') {
    return (
      <>
        {renderAttachmentIcon(attachment.kind)}
        <span className="context-chip-title">{attachment.label}</span>
        <span className="context-chip-meta">{attachment.meta}</span>
      </>
    )
  }
  if (attachment.kind === 'web-link') {
    return (
      <>
        <WebLinkIcon />
        <span className="context-chip-title">{attachment.label}</span>
        <span className="context-chip-meta">Link</span>
      </>
    )
  }
  return (
    <>
      <FileAttachmentIcon />
      <span className="context-chip-title">{attachment.filename}</span>
      <span className="context-chip-meta">p. 3</span>
    </>
  )
}

/** Render the hover preview body tailored to a math cell, sub-expression, note cell, pasted snippet, link, or file. */
function renderAttachmentPreview(attachment: ContextAttachment) {
  if (attachment.kind === 'math-cell') {
    return (
      <div className="context-preview-body">
        <div className="context-preview-header">
          <span className="context-preview-heading">
            <MathIcon /> {attachment.label} · {attachment.meta}
          </span>
          <span className="context-preview-jump">
            <JumpToCellIcon /> Jump
          </span>
        </div>
        <div className="context-preview-formula">
          <InlineLatex latex={attachment.latex} display />
        </div>
        <p className="type-caption">{attachment.note}</p>
        <code className="context-preview-source">{attachment.latex}</code>
      </div>
    )
  }

  if (attachment.kind === 'sub-expression' && attachment.previewLatex !== undefined) {
    const regions = attachment.regions ?? []
    const regionCount = regions.length
    return (
      <div className="context-preview-body">
        <div className="context-preview-header">
          <span className="context-preview-heading">
            <SubExpressionIcon /> {regionCount === 1 ? '1 region' : `${regionCount} separate regions`} in {attachment.cellLabel}
          </span>
          <span className="context-preview-jump">
            <JumpToCellIcon /> Highlight in cell
          </span>
        </div>
        <div className="context-preview-formula highlight-preview">
          <HighlightMath latex={attachment.previewLatex} />
        </div>
        <p className="type-caption">{regionCount > 1 ? 'Each box follows its own glyphs. The highlight is not one rectangle around all of them.' : 'The box follows this region’s glyphs.'}</p>
        <code className="context-preview-source">{regions.join('   ·   ')}</code>
      </div>
    )
  }

  if (attachment.kind === 'sub-expression') {
    return (
      <div className="context-preview-body">
        <div className="context-preview-header">
          <span className="context-preview-heading">
            <SubExpressionIcon /> Sub-expression in {attachment.cellLabel}
          </span>
          <span className="context-preview-jump">
            <JumpToCellIcon /> Highlight in cell
          </span>
        </div>
        <div className="context-preview-formula context-preview-parent-formula">
          {attachment.beforeLatex ? <InlineLatex latex={attachment.beforeLatex} /> : null}
          <span className="context-preview-subexpr-mark">
            <InlineLatex latex={attachment.selectedLatex} />
          </span>
          {attachment.afterLatex ? <InlineLatex latex={attachment.afterLatex} /> : null}
        </div>
        <code className="context-preview-source">{attachment.selectedLatex}</code>
      </div>
    )
  }

  if (attachment.kind === 'markdown-cell') {
    return (
      <div className="context-preview-body">
        <div className="context-preview-header">
          <span className="context-preview-heading">
            <MarkdownIcon /> {attachment.label} · {attachment.meta}
          </span>
          <span className="context-preview-jump">
            <JumpToCellIcon /> Jump
          </span>
        </div>
        <ChatMarkdown content={attachment.markdown} className="context-preview-markdown" />
      </div>
    )
  }

  if (attachment.kind === 'pasted-text') {
    return (
      <div className="context-preview-body">
        <div className="context-preview-header">
          <span className="context-preview-heading">
            <PasteSnippetIcon /> {attachment.label}
          </span>
          <span className="type-caption">{attachment.meta}</span>
        </div>
        <pre className="context-preview-pre">{attachment.snippet}</pre>
      </div>
    )
  }

  if (attachment.kind === 'web-link') {
    return (
      <div className="context-preview-body">
        <div className="context-preview-header">
          <span className="context-preview-heading">
            <WebLinkIcon /> {attachment.domain}
          </span>
          <span className="type-caption">{attachment.label}</span>
        </div>
        <ChatMarkdown content={attachment.excerpt} className="context-preview-markdown" />
        <code className="context-preview-source">{attachment.url}</code>
      </div>
    )
  }

  return (
    <div className="context-preview-body">
      <div className="context-preview-header">
        <span className="context-preview-heading">
          <FileAttachmentIcon /> {attachment.filename}
        </span>
        <span className="type-caption">{attachment.meta}</span>
      </div>
      <ChatMarkdown content={attachment.excerpt} className="context-preview-markdown" />
    </div>
  )
}

/** Render one context attachment pill with a Base UI hover preview card and an optional remove button. */
export function ContextAttachmentChip({ attachment, onRemove }: { attachment: ContextAttachment; onRemove?: (id: string) => void }) {
  /** Remove this context pill from the active chat draft. */
  function handleRemove() {
    onRemove?.(attachment.id)
  }

  const regionName = attachment.kind === 'sub-expression' ? (attachment.regions?.join(', ') ?? attachment.chipLatex) : ''
  const accessibleName = attachment.kind === 'sub-expression' ? `Sub-expression ${regionName} from ${attachment.cellLabel}` : attachment.kind === 'file' ? attachment.filename : attachment.label

  return (
    <span className="context-chip" data-kind={attachment.kind}>
      <PreviewCard.Root>
        <PreviewCard.Trigger render={<button type="button" className="context-chip-trigger" aria-label={`Preview ${accessibleName}`} />} delay={120} closeDelay={100}>
          {renderAttachmentChipContent(attachment)}
        </PreviewCard.Trigger>
        <PreviewCard.Portal>
          <PreviewCard.Positioner sideOffset={8} align="start">
            <PreviewCard.Popup className="primitive-popup context-preview-card">{renderAttachmentPreview(attachment)}</PreviewCard.Popup>
          </PreviewCard.Positioner>
        </PreviewCard.Portal>
      </PreviewCard.Root>
      {onRemove === undefined ? null : (
        <IconTooltip label="Remove context">
          <button type="button" className="context-chip-remove" aria-label={`Remove ${accessibleName}`} onClick={handleRemove}>
            <CloseIcon />
          </button>
        </IconTooltip>
      )}
    </span>
  )
}

/** One piece of a design formula. Zone pieces are the only parts a drag can paint. */
interface FormulaPiece {
  latex: string
  zone?: boolean
  label?: string
  /** `atom` insets the box so neighboring glyphs stay separate. `tight` hugs the glyph instead of the line height. */
  tone?: 'atom' | 'tight'
}

/** A formula on the design page whose highlight is painted by dragging across glyph regions. */
interface HighlightFormulaSpec {
  id: string
  title: string
  hint: string
  cellLabel: string
  pieces: readonly FormulaPiece[]
}

/** A pointer position in viewport pixels. */
interface DragPoint {
  x: number
  y: number
}

/** The axis-aligned box covered by a pointer drag, in viewport pixels. */
interface DragBox {
  left: number
  top: number
  right: number
  bottom: number
}

/** An in-progress drag on one highlight surface. */
interface DragSession {
  pointerId: number
  x: number
  y: number
  started: boolean
}

/** The prose cell a drag can select as a whole line. */
const proseHighlight = {
  id: 'cell-note',
  title: 'Whole cell',
  hint: 'Drag across the note to highlight the whole Markdown cell as one line.',
  cellLabel: 'Cell 1',
  markdown: 'Assume $X \\in \\mathbb{R}^{N \\times d}$ has full column rank and $\\lambda > 0$.',
}

/** Four formulas whose committed highlights are not a single rectangle. */
const highlightFormulas: readonly HighlightFormulaSpec[] = [
  {
    id: 'radical-parts',
    title: 'Disjoint regions',
    hint: 'Drag across the index and the numerator. Each lights as its own box, with a gap between them.',
    cellLabel: 'Cell 5',
    pieces: [{ latex: String.raw`\sqrt{1+\sqrt{1+x^{2}}}+\sqrt[` }, { latex: '3', zone: true, label: 'the index 3' }, { latex: String.raw`]{\frac{` }, { latex: 'a+b', zone: true, label: 'the numerator a+b' }, { latex: String.raw`}{c}}` }],
  },
  {
    id: 'numerator-atoms',
    title: 'Separate atoms',
    hint: 'Drag across x − 2. Each atom keeps its own box.',
    cellLabel: 'Cell 6',
    pieces: [{ latex: String.raw`\frac{\left(x+1\right)\left(x-2\right)}{x^{2}+3x+2}=\frac{` }, { latex: 'x', zone: true, label: 'x', tone: 'atom' }, { latex: '-', zone: true, label: 'the minus', tone: 'atom' }, { latex: '2', zone: true, label: '2', tone: 'atom' }, { latex: String.raw`}{x+2}` }],
  },
  {
    id: 'stepped-fraction',
    title: 'Stepped fraction',
    hint: 'Drag across the fraction. The wide numerator and the narrow denominator each get a box, so the outline steps.',
    cellLabel: 'Cell 7',
    pieces: [{ latex: String.raw`\frac{` }, { latex: String.raw`a+\frac{b}{c}`, zone: true, label: 'the wide numerator' }, { latex: '}{' }, { latex: 'd', zone: true, label: 'the narrow denominator', tone: 'tight' }, { latex: String.raw`}+e` }],
  },
  {
    id: 'tall-union',
    title: 'Tall operator',
    hint: 'Drag across the union and B. The union box, limits included, is taller than the box on B.',
    cellLabel: 'Cell 8',
    pieces: [{ latex: String.raw`\bigcup_{i=1}^{n}\left(A_{i}\cap B\right)\subseteq\left(` }, { latex: String.raw`\bigcup_{i=1}^{n}A_{i}`, zone: true, label: 'the tall union' }, { latex: String.raw`\right)\cap ` }, { latex: 'B', zone: true, label: 'B', tone: 'tight' }],
  },
]

/** How far a pointer must move, in pixels, before the gesture counts as a highlight instead of a click. */
const highlightDragThreshold = 5

/** Permit KaTeX to mark highlight regions with a class, and reject every other HTML-producing command. */
function trustHighlightClass(context: TrustContext) {
  return context.command === '\\htmlClass'
}

/** Typeset a formula, leaving each `\htmlClass{hl-zone}` region as its own span. */
function HighlightMath({ latex }: { latex: string }) {
  const html = katex.renderToString(latex, {
    throwOnError: false,
    strict: 'ignore',
    trust: trustHighlightClass,
  })
  return <span className="chat-latex highlight-math" dangerouslySetInnerHTML={{ __html: html }} />
}

/** Choose the KaTeX class for a paintable region. Atoms stay visually separate, and tight regions hug the glyph. */
function highlightClass(piece: FormulaPiece) {
  if (piece.tone === 'atom') return 'hl-zone hl-atom'
  if (piece.tone === 'tight') return 'hl-zone hl-tight'
  return 'hl-zone'
}

/** Build a KaTeX string. Pass a lit mask to mark only those zones; pass null to mark every zone so a drag can hit-test them. */
function composeHighlightLatex(pieces: readonly FormulaPiece[], lit: readonly boolean[] | null) {
  let latex = ''
  let zoneIndex = 0
  for (const piece of pieces) {
    if (piece.zone !== true) {
      latex += piece.latex
      continue
    }
    const mark = lit === null || lit[zoneIndex] === true
    latex += mark ? `\\htmlClass{${highlightClass(piece)}}{${piece.latex}}` : piece.latex
    zoneIndex += 1
  }
  return latex
}

/** Count the paintable regions in a formula. */
function countZones(pieces: readonly FormulaPiece[]) {
  let count = 0
  for (const piece of pieces) {
    if (piece.zone === true) count += 1
  }
  return count
}

/** Build an all-clear highlight of the given length. */
function emptyLit(count: number) {
  const lit: boolean[] = []
  for (let index = 0; index < count; index += 1) lit.push(false)
  return lit
}

/** Build the starting highlight map, with nothing painted. */
function initialHighlights() {
  const highlights: Record<string, readonly boolean[]> = {}
  for (const spec of highlightFormulas) highlights[spec.id] = emptyLit(countZones(spec.pieces))
  return highlights
}

/** Find one design formula by its id. */
function findHighlightFormula(id: string) {
  for (const spec of highlightFormulas) {
    if (spec.id === id) return spec
  }
  return undefined
}

/** List the spoken labels of the regions a drag painted. */
function selectedZoneLabels(pieces: readonly FormulaPiece[], lit: readonly boolean[]) {
  const labels: string[] = []
  let zoneIndex = 0
  for (const piece of pieces) {
    if (piece.zone !== true) continue
    if (lit[zoneIndex] === true) labels.push(piece.label ?? piece.latex)
    zoneIndex += 1
  }
  return labels
}

/** List the LaTeX source of the regions a drag painted, without gluing them into one expression. */
function selectedZoneLatex(pieces: readonly FormulaPiece[], lit: readonly boolean[]) {
  const sources: string[] = []
  let zoneIndex = 0
  for (const piece of pieces) {
    if (piece.zone !== true) continue
    if (lit[zoneIndex] === true) sources.push(piece.latex)
    zoneIndex += 1
  }
  return sources
}

/** Join region labels into one sentence fragment. */
function joinLabels(labels: readonly string[]) {
  if (labels.length <= 1) return labels[0] ?? ''
  if (labels.length === 2) return `${labels[0]} and ${labels[1]}`
  const head: string[] = []
  for (let index = 0; index < labels.length - 1; index += 1) head.push(labels[index])
  return `${head.join(', ')}, and ${labels[labels.length - 1]}`
}

/** Describe the boxes a drag left behind. */
function describeHighlight(spec: HighlightFormulaSpec, lit: readonly boolean[]) {
  const labels = selectedZoneLabels(spec.pieces, lit)
  if (labels.length === 0) return `${spec.title}: drag across the formula to highlight a region.`
  if (labels.length === 1) return `${spec.title}: highlighted ${labels[0]} as one box.`
  return `${spec.title}: highlighted ${joinLabels(labels)} as ${labels.length} separate boxes.`
}

/** Build the chat chip for a painted highlight. Returns nothing when the drag missed every region. */
function attachmentForHighlight(spec: HighlightFormulaSpec, lit: readonly boolean[]): ContextAttachment | null {
  const regions = selectedZoneLatex(spec.pieces, lit)
  if (regions.length === 0) return null
  const first = regions[0]
  let mask = ''
  for (const painted of lit) mask += painted ? '1' : '0'
  return {
    id: `highlight-${spec.id}-${mask}`,
    kind: 'sub-expression',
    cellLabel: spec.cellLabel,
    chipLatex: first,
    regions,
    previewLatex: composeHighlightLatex(spec.pieces, lit),
    beforeLatex: '',
    selectedLatex: first,
    afterLatex: '',
  }
}

/** Build the axis-aligned box covered by a pointer drag. */
function dragBox(start: DragPoint, end: DragPoint): DragBox {
  return {
    left: Math.min(start.x, end.x),
    top: Math.min(start.y, end.y),
    right: Math.max(start.x, end.x),
    bottom: Math.max(start.y, end.y),
  }
}

/** Measure how far the pointer has moved from the drag origin, in pixels. */
function dragDistance(start: DragPoint, end: DragPoint) {
  return Math.hypot(end.x - start.x, end.y - start.y)
}

/** Report whether a glyph box meets the drag box, with a few pixels of slop so a thin index is easy to catch. */
function dragHits(target: DOMRect, drag: DragBox) {
  const slop = 6
  return target.left - slop < drag.right && target.right + slop > drag.left && target.top - slop < drag.bottom && target.bottom + slop > drag.top
}

/** Mark the regions whose glyph boxes meet the current drag. */
function paintDraggedZones(stage: HTMLElement, drag: DragBox) {
  const zones = stage.querySelectorAll('.hl-zone')
  for (let index = 0; index < zones.length; index += 1) {
    zones.item(index).classList.toggle('is-lit', dragHits(zones.item(index).getBoundingClientRect(), drag))
  }
}

/** Apply a committed highlight onto the regions already in the formula. */
function applyLitClasses(stage: HTMLElement, lit: readonly boolean[]) {
  const zones = stage.querySelectorAll('.hl-zone')
  for (let index = 0; index < zones.length; index += 1) {
    zones.item(index).classList.toggle('is-lit', lit[index] === true)
  }
}

/** Clear every region highlight while a new drag is starting. */
function clearLitClasses(stage: HTMLElement) {
  const zones = stage.querySelectorAll('.hl-zone')
  for (let index = 0; index < zones.length; index += 1) {
    zones.item(index).classList.remove('is-lit')
  }
}

/** Read which regions are painted at the end of a drag. */
function readLitClasses(stage: HTMLElement) {
  const zones = stage.querySelectorAll('.hl-zone')
  const lit: boolean[] = []
  for (let index = 0; index < zones.length; index += 1) {
    lit.push(zones.item(index).classList.contains('is-lit'))
  }
  return lit
}

/** Icon actions that send the current highlight, or the whole note, into chat. */
function HighlightActions({ id, addLabel, onAdd, onQuickAction }: { id: string; addLabel: string; onAdd: (id: string) => void; onQuickAction: (id: string, action: string) => void }) {
  /** Attach this row’s current highlight to the chat tray. */
  function handleAdd() {
    onAdd(id)
  }

  /** Record an explain request against this row’s highlight. */
  function handleExplain() {
    onQuickAction(id, 'Explain in chat')
  }

  /** Record a simplify request against this row’s highlight. */
  function handleSimplify() {
    onQuickAction(id, 'Simplify expression')
  }

  /** Record a copy of this row’s highlighted LaTeX. */
  function handleCopy() {
    onQuickAction(id, 'Copied LaTeX')
  }

  return (
    <div className="selectable-cell-actions">
      <IconTooltip label={addLabel} shortcut="Cmd L">
        <button type="button" className="primitive-icon-button primitive-icon-primary" aria-label={addLabel} onClick={handleAdd}>
          <AddToChatIcon />
        </button>
      </IconTooltip>
      <IconTooltip label="Ask agent to explain" shortcut="Cmd J">
        <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label="Explain in chat" onClick={handleExplain}>
          <AssistantSparklesIcon />
        </button>
      </IconTooltip>
      <IconTooltip label="Simplify expression">
        <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label="Simplify expression" onClick={handleSimplify}>
          <SymbolicComputeIcon />
        </button>
      </IconTooltip>
      <IconTooltip label="Copy LaTeX" shortcut="Cmd C">
        <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label="Copy LaTeX" onClick={handleCopy}>
          <CopyIcon />
        </button>
      </IconTooltip>
    </div>
  )
}

/** One formula the pointer highlights by dragging. Each paintable region paints its own box. */
function HighlightFormulaRow({ spec, lit, onCommit, onAdd, onQuickAction }: { spec: HighlightFormulaSpec; lit: readonly boolean[]; onCommit: (id: string, lit: readonly boolean[]) => void; onAdd: (id: string) => void; onQuickAction: (id: string, action: string) => void }) {
  const stageRef = useRef<HTMLDivElement>(null)
  const dragOrigin = useRef<DragSession | null>(null)
  const html = composeHighlightLatex(spec.pieces, null)

  /** Restore the committed boxes after KaTeX replaces the formula markup. */
  function syncLitClasses() {
    const stage = stageRef.current
    if (stage === null) return
    applyLitClasses(stage, lit)
  }
  useLayoutEffect(syncLitClasses, [lit, html])

  /** Begin a highlight gesture without clearing the previous boxes until the pointer actually moves. */
  function handlePointerDown(event: ReactPointerEvent<HTMLDivElement>) {
    if (event.button !== 0) return
    event.currentTarget.setPointerCapture(event.pointerId)
    dragOrigin.current = { pointerId: event.pointerId, x: event.clientX, y: event.clientY, started: false }
  }

  /** Paint every region the drag rectangle touches, then drop the rectangle. The boxes that remain are the selection. */
  function handlePointerMove(event: ReactPointerEvent<HTMLDivElement>) {
    const origin = dragOrigin.current
    if (origin === null || origin.pointerId !== event.pointerId) return
    const point = { x: event.clientX, y: event.clientY }
    if (dragDistance(origin, point) < highlightDragThreshold) return
    if (origin.started !== true) {
      clearLitClasses(event.currentTarget)
      origin.started = true
    }
    paintDraggedZones(event.currentTarget, dragBox(origin, point))
  }

  /** Keep the painted regions when the drag moved, and restore the previous highlight when it was only a click. */
  function handlePointerUp(event: ReactPointerEvent<HTMLDivElement>) {
    const origin = dragOrigin.current
    dragOrigin.current = null
    if (origin === null || origin.pointerId !== event.pointerId) return
    if (origin.started !== true) {
      applyLitClasses(event.currentTarget, lit)
      return
    }
    onCommit(spec.id, readLitClasses(event.currentTarget))
  }

  /** End the gesture if the pointer is cancelled, keeping whatever boxes were already painted. */
  function handlePointerCancel(event: ReactPointerEvent<HTMLDivElement>) {
    const origin = dragOrigin.current
    dragOrigin.current = null
    if (origin === null || origin.started !== true) return
    onCommit(spec.id, readLitClasses(event.currentTarget))
  }

  return (
    <div className="highlight-row">
      <div ref={stageRef} className="highlight-stage" aria-label={`${spec.title}. ${spec.hint}`} onPointerDown={handlePointerDown} onPointerMove={handlePointerMove} onPointerUp={handlePointerUp} onPointerCancel={handlePointerCancel}>
        <HighlightMath latex={html} />
      </div>
      <HighlightActions id={spec.id} addLabel="Add highlight to chat" onAdd={onAdd} onQuickAction={onQuickAction} />
      <p className="highlight-hint">{spec.hint}</p>
    </div>
  )
}

/** A Markdown note selected by dragging across the line, which highlights as one line rather than glyph boxes. */
function HighlightProseRow({ lit, onCommit, onAdd, onQuickAction }: { lit: boolean; onCommit: (lit: boolean) => void; onAdd: (id: string) => void; onQuickAction: (id: string, action: string) => void }) {
  const dragOrigin = useRef<DragSession | null>(null)

  /** Begin a drag that can select the whole note. */
  function handlePointerDown(event: ReactPointerEvent<HTMLDivElement>) {
    if (event.button !== 0) return
    event.currentTarget.setPointerCapture(event.pointerId)
    dragOrigin.current = { pointerId: event.pointerId, x: event.clientX, y: event.clientY, started: false }
  }

  /** Light the note once the pointer has moved across it. */
  function handlePointerMove(event: ReactPointerEvent<HTMLDivElement>) {
    const origin = dragOrigin.current
    if (origin === null || origin.pointerId !== event.pointerId) return
    const point = { x: event.clientX, y: event.clientY }
    if (dragDistance(origin, point) < highlightDragThreshold) return
    origin.started = true
    const prose = event.currentTarget.querySelector('.highlight-prose')
    if (!(prose instanceof HTMLElement)) return
    prose.classList.toggle('is-lit', dragHits(prose.getBoundingClientRect(), dragBox(origin, point)))
  }

  /** Commit the line highlight when the drag crossed the note. */
  function handlePointerUp(event: ReactPointerEvent<HTMLDivElement>) {
    const origin = dragOrigin.current
    dragOrigin.current = null
    if (origin === null || origin.pointerId !== event.pointerId || origin.started !== true) return
    const prose = event.currentTarget.querySelector('.highlight-prose')
    onCommit(prose instanceof HTMLElement && prose.classList.contains('is-lit'))
  }

  return (
    <div className="highlight-row">
      <div className="highlight-stage" aria-label={`${proseHighlight.title}. ${proseHighlight.hint}`} onPointerDown={handlePointerDown} onPointerMove={handlePointerMove} onPointerUp={handlePointerUp}>
        <div className={lit ? 'highlight-prose is-lit' : 'highlight-prose'}>
          <ChatMarkdown content={proseHighlight.markdown} />
        </div>
      </div>
      <HighlightActions id={proseHighlight.id} addLabel="Add cell to chat" onAdd={onAdd} onQuickAction={onQuickAction} />
      <p className="highlight-hint">{proseHighlight.hint}</p>
    </div>
  )
}

/** Demonstrate highlighting sub-expressions by dragging, including selections that are not one rectangle, and sending that highlight to chat. */
export function SelectionToChat() {
  const [highlights, setHighlights] = useState(initialHighlights)
  const [proseLit, setProseLit] = useState(false)
  const [attached, setAttached] = useState<readonly ContextAttachment[]>([])
  const [status, setStatus] = useState('Drag across a formula. The highlight follows each region, so it can be several boxes, a step, or a tall operator beside a short one.')

  /** Store the boxes a drag left on one formula and describe them. Later drags keep the highlights already stored for other formulas. */
  function handleCommit(id: string, lit: readonly boolean[]) {
    /** Add this formula’s boxes to the latest highlight map. */
    function paintHighlight(current: Readonly<Record<string, readonly boolean[]>>) {
      return { ...current, [id]: lit }
    }
    setHighlights(paintHighlight)
    const spec = findHighlightFormula(id)
    if (spec === undefined) return
    setStatus(describeHighlight(spec, lit))
  }

  /** Store whether the note line is highlighted. */
  function handleProseCommit(lit: boolean) {
    setProseLit(lit)
    setStatus(lit ? 'Whole cell: highlighted the note as one line.' : 'Whole cell: drag across the note to highlight it.')
  }

  /** Attach the highlighted regions, or the whole note, without duplicating an identical pill. */
  function addHighlightToChat(id: string) {
    if (id === proseHighlight.id) {
      if (proseLit !== true) {
        setStatus('Drag across the note before adding the cell to chat.')
        return
      }
      const attachment: ContextAttachment = {
        id: proseHighlight.id,
        kind: 'markdown-cell',
        label: proseHighlight.cellLabel,
        meta: 'Assumptions',
        markdown: 'Assume $X \\in \\mathbb{R}^{N \\times d}$ has full column rank and $\\lambda > 0$.',
      }
      /** Check whether the note is already in the tray. */
      function hasNote(existing: ContextAttachment) {
        return existing.id === attachment.id
      }
      if (!attached.some(hasNote)) setAttached([...attached, attachment])
      setStatus('Added the note cell to chat. Hover the chip to preview it.')
      return
    }
    const spec = findHighlightFormula(id)
    if (spec === undefined) return
    const lit = highlights[spec.id]
    const attachment = attachmentForHighlight(spec, lit)
    if (attachment === null) {
      setStatus(`${spec.title}: drag across the formula before adding it to chat.`)
      return
    }
    const selectedAttachment = attachment
    /** Check whether this exact set of regions is already in the tray. */
    function hasSameHighlight(existing: ContextAttachment) {
      return existing.id === selectedAttachment.id
    }
    if (!attached.some(hasSameHighlight)) setAttached([...attached, attachment])
    setStatus(`Added ${joinLabels(selectedZoneLabels(spec.pieces, lit))} to chat. Hover the chip to see the same boxes.`)
  }

  /** Record an explain, simplify, or copy against the highlight on one row. */
  function handleQuickAction(id: string, action: string) {
    if (id === proseHighlight.id) {
      setStatus(proseLit ? `${action} on the note cell.` : 'Drag across the note first.')
      return
    }
    const spec = findHighlightFormula(id)
    if (spec === undefined) return
    const labels = selectedZoneLabels(spec.pieces, highlights[spec.id])
    if (labels.length === 0) {
      setStatus(`Drag across ${spec.title} before using ${action}.`)
      return
    }
    setStatus(`${action} on ${joinLabels(labels)}.`)
  }

  /** Remove one attached pill from the preview tray. */
  function removeAttached(id: string) {
    /** Keep every attachment except the removed id. */
    function keepOther(item: ContextAttachment) {
      return item.id !== id
    }
    setAttached(attached.filter(keepOther))
  }

  /** Render one attached context pill inside the live composer strip. */
  function renderAttachedChip(item: ContextAttachment) {
    return <ContextAttachmentChip key={item.id} attachment={item} onRemove={removeAttached} />
  }

  /** Render one formula row from the current highlight map. */
  function renderFormulaRow(spec: HighlightFormulaSpec) {
    return <HighlightFormulaRow key={spec.id} spec={spec} lit={highlights[spec.id] ?? emptyLit(countZones(spec.pieces))} onCommit={handleCommit} onAdd={addHighlightToChat} onQuickAction={handleQuickAction} />
  }

  return (
    <div className="selection-demo">
      <p className="highlight-lead">Drag across the glyphs. A click does not select anything. The highlight that remains follows each region, including gaps, steps, and a tall operator beside a shorter symbol.</p>
      {highlightFormulas.map(renderFormulaRow)}
      <HighlightProseRow lit={proseLit} onCommit={handleProseCommit} onAdd={addHighlightToChat} onQuickAction={handleQuickAction} />
      <div className="context-tray">
        <span className="context-tray-label">Attached to chat (hover to preview):</span>
        <div className="context-chip-list">{attached.length > 0 ? attached.map(renderAttachedChip) : <span className="type-caption">No context attached yet. Drag a highlight, then use the add icon.</span>}</div>
      </div>
      <p className="primitive-status">{status}</p>
    </div>
  )
}

/** Show all chat context pill kinds—cells, sub-expressions, long pasted snippets, links, and files—with hover previews and an @ attach menu. */
export function ChatContextAttachments() {
  const [attachments, setAttachments] = useState<readonly ContextAttachment[]>(sampleContextCatalog)

  /** Remove one context chip from the active list. */
  function handleRemove(id: string) {
    /** Retain every context item except the removed chip. */
    function keepOther(item: ContextAttachment) {
      return item.id !== id
    }
    setAttachments(attachments.filter(keepOther))
  }

  /** Attach or restore a context item chosen from the @ context menu. */
  function handleAttachFromMenu(event: { currentTarget: EventTarget | null }) {
    const target = event.currentTarget
    if (!(target instanceof HTMLElement)) return
    const itemId = target.dataset.contextId
    /** Match the requested catalog item by id. */
    function matchesCatalogId(entry: ContextAttachment) {
      return entry.id === itemId
    }
    const found = sampleContextCatalog.find(matchesCatalogId)
    if (found === undefined) return
    const selectedAttachment = found
    /** Check whether this item is already attached. */
    function alreadyAttached(entry: ContextAttachment) {
      return entry.id === selectedAttachment.id
    }
    if (!attachments.some(alreadyAttached)) {
      setAttachments([...attachments, selectedAttachment])
    }
  }

  /** Restore all six sample context kinds at once. */
  function resetAllAttachments() {
    setAttachments(sampleContextCatalog)
  }

  /** Render one context pill with its hover preview card. */
  function renderChip(item: ContextAttachment) {
    return <ContextAttachmentChip key={item.id} attachment={item} onRemove={handleRemove} />
  }

  /** Render one menu item inside the @ Add context menu. */
  function renderCatalogMenuItem(item: ContextAttachment) {
    const title = item.kind === 'sub-expression' ? `Sub-expression (${item.cellLabel})` : item.kind === 'file' ? item.filename : item.label
    return (
      <Menu.Item key={item.id} className="primitive-item" data-context-id={item.id} onClick={handleAttachFromMenu}>
        <span className="primitive-item-label">
          {renderAttachmentIcon(item.kind)} {title}
        </span>
        <span className="primitive-kbd">@</span>
      </Menu.Item>
    )
  }

  return (
    <div className="notebook-stack notebook-wide">
      <div className="context-composer-strip">
        <Menu.Root>
          <IconTooltip label="Add context (@ cell, sub-expr, paste, link, file)" shortcut="@">
            <Menu.Trigger className="context-add-button" aria-label="Add context">
              <AttachContextIcon /> Add context
            </Menu.Trigger>
          </IconTooltip>
          <Menu.Portal>
            <Menu.Positioner sideOffset={6} align="start">
              <Menu.Popup className="primitive-popup">{sampleContextCatalog.map(renderCatalogMenuItem)}</Menu.Popup>
            </Menu.Positioner>
          </Menu.Portal>
        </Menu.Root>
        {attachments.map(renderChip)}
        {attachments.length < sampleContextCatalog.length ? (
          <button type="button" className="notebook-chip" onClick={resetAllAttachments}>
            Restore all ({sampleContextCatalog.length})
          </button>
        ) : null}
      </div>
      <p className="primitive-status">Hover or focus any context pill to inspect its rendered LaTeX, parent expression, pasted lines, URL abstract, or PDF excerpt.</p>
    </div>
  )
}
