/**
 * Keep automatic/manual subject selection in the status bar and an optional hint with progressive explanation inside the active block. Use the whole current page as context; never insert an answer or expose separate context controls.
 *
 * @file
 */
import { createPortal } from 'react-dom'
import { useEffect, useRef, useState } from 'react'
import type { ChangeEvent } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Lightbulb, X } from 'lucide-react'
import { Button } from '#/component-library'
import { MarkdownDocument } from '#/components/markdown-cell'
import { notebookCommands, usePageSelection } from '#/notebook/use-page-state'
import type { Page } from '#/notebook/page'
import type { NotebookCell } from '#/notebook/notebook-cells'
import { blockIndex } from '#/notebook/notebook-blocks'
import { mathSection } from './math-context'
import { builtinModes } from './math-modes'
import type { MathMode, MathPreferences } from './math-modes'
import { detectMathMode, proposeMath } from './math-assistant'
import type { MathProposal, ModeSuggestion } from './math-assistant'
import './math-help.css'

/** Invalidate a hint whenever any part of its page context changes. */
function wholePage(page: Page) {
  return page
}
/** Show actual local-model or persistence failures beside their controls. */
function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

/** Render subject controls below the workspace and a single hint action inside the selected block. */
export function MathHelpPanel({ pageId, cellId, preferences, hintRequest }: { pageId: string; cellId?: string; preferences: MathPreferences; hintRequest: number }) {
  const page = usePageSelection(pageId, wholePage)
  const { updatePage } = notebookCommands(useQueryClient())
  const section = page ? mathSection(page, cellId) : undefined
  const modes = [...builtinModes, ...preferences.modes]
  const [suggestion, setSuggestion] = useState<ModeSuggestion>()
  const [slot, setSlot] = useState<HTMLElement | null>(null)
  const [proposal, setProposal] = useState<MathProposal>()
  const [hintBusy, setHintBusy] = useState(false)
  const [detecting, setDetecting] = useState(false)
  const [hintError, setHintError] = useState('')
  const [subjectError, setSubjectError] = useState('')
  const pendingHint = useRef<AbortController | null>(null)
  const pendingDetection = useRef<AbortController | null>(null)
  const previousRequest = useRef(hintRequest)
  const modeId = (section?.modeId ?? suggestion?.modeId) || preferences.default_mode
  /** Resolve an available subject without replacing a missing explicit custom mode. */
  function matchesMode(mode: MathMode) {
    return mode.id === modeId
  }
  const mode = modes.find(matchesMode)
  const context = section?.context ?? ''
  const contextKey = JSON.stringify({ pageId, root: section?.rootId, cell: section?.cellId, context, manualMode: section?.modeId, preferences })
  const latestKey = useRef(contextKey)
  latestKey.current = contextKey

  /** Cancel stale work and discard hints for an earlier problem or revision. */
  function invalidate() {
    pendingHint.current?.abort()
    pendingDetection.current?.abort()
    setHintBusy(false)
    setDetecting(false)
    setProposal(undefined)
    setSuggestion(undefined)
    setHintError('')
    setSubjectError('')
    /** Stop local inference when the page closes or its context changes. */
    function stop() {
      pendingHint.current?.abort()
      pendingDetection.current?.abort()
    }
    return stop
  }
  useEffect(invalidate, [contextKey])

  /** Detect a subject after typing settles; give an explicit hint request priority over background inference. */
  function autoDetect() {
    if (hintBusy || suggestion || section?.modeId || !preferences.suggest_modes || !page?.cells.length || !context.trim() || context.length > 20000) return
    const controller = new AbortController()
    pendingDetection.current = controller
    /** Read only the current page and accept only a response for this revision. */
    async function detect() {
      setDetecting(true)
      try {
        const result = await detectMathMode(preferences.model, modes, context, controller.signal)
        if (!controller.signal.aborted && latestKey.current === contextKey) setSuggestion(result)
      } catch (error) {
        if (!controller.signal.aborted && latestKey.current === contextKey) setSubjectError(errorMessage(error))
      } finally {
        if (pendingDetection.current === controller) setDetecting(false)
      }
    }
    const timer = setTimeout(detect, 1800)
    /** Release both a scheduled detection and any request already started by it. */
    function stop() {
      clearTimeout(timer)
      controller.abort()
    }
    return stop
  }
  useEffect(autoDetect, [contextKey, hintBusy, suggestion, preferences.suggest_modes])

  /** Store a manual section choice; the Auto option removes that override. */
  function selectMode(event: ChangeEvent<HTMLSelectElement>) {
    if (!section) return
    const sourceSection = section
    const id = event.target.value || undefined
    /** Keep all text, graphs, nesting, and unrelated subjects intact. */
    function change(current: Page): Page {
      if (latestKey.current !== contextKey) throw new Error('The selected problem changed. Choose its subject again.')
      /** Update only the current problem's root block. */
      function assign(cell: NotebookCell): NotebookCell {
        return cell.cellId === sourceSection.rootId ? { ...cell, mathMode: id } : cell
      }
      return { ...current, cells: current.cells.map(assign) }
    }
    try {
      updatePage(pageId, change)
    } catch (error) {
      setSubjectError(errorMessage(error))
    }
  }
  /** Find the selected block's existing inline slot after its render commits. */
  function locateSlot() {
    setSlot(section ? document.querySelector<HTMLElement>(`[data-math-help-slot="${CSS.escape(section.cellId)}"]`) : null)
  }
  useEffect(locateSlot, [section?.cellId, pageId, page?.cells])

  /** Request a hint or expand its explanation, retaining the existing hint while more detail loads. */
  async function requestHint(previousHint: string) {
    pendingHint.current?.abort()
    pendingDetection.current?.abort()
    setDetecting(false)
    setHintError('')
    if (!previousHint) setProposal(undefined)
    if (!section || !mode) {
      setHintError('Choose an available subject for this problem.')
      return
    }
    if (context.length > 20000) {
      setHintError('This page exceeds the local model’s 20,000-character context limit. Nothing was sent or truncated.')
      return
    }
    const controller = new AbortController()
    pendingHint.current = controller
    setHintBusy(true)
    try {
      const result = await proposeMath(preferences.model, mode, context, '', true, controller.signal, previousHint)
      if (!controller.signal.aborted && latestKey.current === contextKey) setProposal(result)
    } catch (error) {
      if (!controller.signal.aborted && latestKey.current === contextKey) setHintError(errorMessage(error))
    } finally {
      if (pendingHint.current === controller) setHintBusy(false)
    }
  }
  /** Start with a short conceptual hint for the current problem. */
  function hint() {
    void requestHint('')
  }
  /** Build on the displayed hint without inserting a step into the notebook. */
  function explainHint() {
    if (proposal) void requestHint(proposal.explanation)
  }
  /** Dismiss a result or cancel a pending hint without changing the document. */
  function dismiss() {
    pendingHint.current?.abort()
    setHintBusy(false)
    setProposal(undefined)
    setHintError('')
  }
  /** Keep the existing math-help keyboard command pointed at the same inline hint action. */
  function commandHint() {
    if (hintRequest === previousRequest.current) return
    previousRequest.current = hintRequest
    void hint()
  }
  useEffect(commandHint, [hintRequest])
  /** Render both built-in and settings-defined subjects. */
  function option(item: MathMode) {
    return (
      <option key={item.id} value={item.id}>
        {item.title}
      </option>
    )
  }
  const subjectLabel = mode?.title ?? `Missing: ${modeId}`
  return (
    <>
      <footer className="math-statusbar" aria-label="Math status">
        <span>{section && page ? `Block ${blockIndex(page.cells, section.cellId) + 1}` : 'Select a problem'}</span>
        <select aria-label="Math subject" title={subjectError || suggestion?.reason || 'Detect the subject automatically, or choose one manually'} value={section?.modeId ?? ''} onChange={selectMode} disabled={!section}>
          <option value="">Auto · {detecting ? 'Detecting…' : subjectLabel}</option>
          {!mode && section?.modeId && <option value={modeId}>{subjectLabel}</option>}
          {modes.map(option)}
        </select>
        {subjectError && (
          <span role="status" title={subjectError}>
            Subject detection unavailable
          </span>
        )}
      </footer>
      {slot &&
        createPortal(
          <div className="math-hint" aria-label="Hint for selected problem">
            <Button variant="quiet" onClick={hint} disabled={hintBusy || !mode} className="math-hint-trigger">
              <Lightbulb size={14} aria-hidden="true" />
              Hint
            </Button>
            {(hintBusy || proposal || hintError) && (
              <aside className="math-hint-result" aria-live="polite" aria-busy={hintBusy}>
                <div>
                  {proposal && <MarkdownDocument markdown={proposal.explanation} />}
                  {hintBusy && <p role="status">Thinking…</p>}
                  {hintError && <p role="alert">{hintError}</p>}
                  {proposal && (
                    <Button variant="quiet" className="math-hint-trigger" onClick={explainHint} disabled={hintBusy || !mode}>
                      Explain more
                    </Button>
                  )}
                </div>
                <Button variant="icon" onClick={dismiss} aria-label={hintBusy ? 'Cancel hint' : 'Dismiss hint'}>
                  <X size={14} aria-hidden="true" />
                </Button>
              </aside>
            )}
          </div>,
          slot,
        )}
    </>
  )
}
