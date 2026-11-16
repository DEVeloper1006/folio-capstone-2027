/**
 * Show notebook chrome around live math and Markdown cells: the Lucide icon palette with tooltips, six real MathLive `LatexCell` states, inline completions, speech dictation, and the command palette shell.
 *
 * @file
 */

import { useCallback, useState } from 'react'
import type { ReactNode } from 'react'
import { Button } from '#/component-library/index.ts'
import { CommandPaletteView } from '#/components/command-palette-view.tsx'
import type { CommandPaletteAction } from '#/components/command-palette-view.tsx'
import { LatexCell } from '#/components/latex-cell.tsx'
import {
  AcceptIcon,
  AddToChatIcon,
  AssistantSparklesIcon,
  AttachContextIcon,
  AutocompleteIcon,
  BoldIcon,
  CellComputingIcon,
  CellEditingIcon,
  CellEmptyIcon,
  CellErrorIcon,
  CellFocusedIcon,
  CellPatchIcon,
  CellSelectedIcon,
  CodeIcon,
  CopyIcon,
  DeleteIcon,
  ItalicIcon,
  KeyboardIcon,
  MarkdownIcon,
  MathIcon,
  MicrophoneIcon,
  PythonSandboxIcon,
  ReferenceLookupIcon,
  SearchIcon,
  SendIcon,
  SettingsIcon,
  StopIcon,
  SubExpressionIcon,
  SymbolicComputeIcon,
  VerifyStepIcon,
} from '#/component-library/icons/folio-icons.tsx'
import { InlineLatex } from './chat-math.tsx'
import { IconTooltip } from './icon-tooltip.tsx'

/** One named icon and the tooltip explanation shown on hover or focus. */
interface IconSample {
  id: string
  label: string
  shortcut?: string
  Icon: () => ReactNode
}

/** Describe one live `LatexCell` state specimen, its starting LaTeX expression, and optional evaluation or diagnostic footer. */
interface LiveCellStateSample {
  id: 'empty' | 'focused' | 'editing' | 'selected' | 'computing' | 'error'
  cellId: string
  label: string
  detail: string
  initialLatex: string
  diagnostic?: string
  Icon: () => ReactNode
}

const iconSamples: readonly IconSample[] = [
  { id: 'microphone', label: 'Speech to text', shortcut: 'Cmd Shift V', Icon: MicrophoneIcon },
  { id: 'autocomplete', label: 'Inline suggestion', shortcut: 'Tab', Icon: AutocompleteIcon },
  { id: 'assistant', label: 'Ask assistant', shortcut: 'Cmd J', Icon: AssistantSparklesIcon },
  { id: 'add-chat', label: 'Add selection to chat', shortcut: 'Cmd L', Icon: AddToChatIcon },
  { id: 'attach', label: 'Attach context', shortcut: '@', Icon: AttachContextIcon },
  { id: 'subexpr', label: 'Sub-expression', Icon: SubExpressionIcon },
  { id: 'cas', label: 'Symbolic evaluate', Icon: SymbolicComputeIcon },
  { id: 'verify', label: 'Verify proof step', Icon: VerifyStepIcon },
  { id: 'patch', label: 'Propose cell diff', Icon: CellPatchIcon },
  { id: 'python', label: 'Python sandbox', Icon: PythonSandboxIcon },
  { id: 'reference', label: 'Reference lookup', Icon: ReferenceLookupIcon },
  { id: 'math', label: 'Math cell', shortcut: 'Opt Cmd M', Icon: MathIcon },
  { id: 'markdown', label: 'Markdown cell', shortcut: 'Opt Cmd E', Icon: MarkdownIcon },
  { id: 'bold', label: 'Bold', shortcut: 'Cmd B', Icon: BoldIcon },
  { id: 'italic', label: 'Italic', shortcut: 'Cmd I', Icon: ItalicIcon },
  { id: 'code', label: 'Inline code', shortcut: 'Cmd E', Icon: CodeIcon },
  { id: 'search', label: 'Expression search', shortcut: '/', Icon: SearchIcon },
  { id: 'settings', label: 'Page display', Icon: SettingsIcon },
  { id: 'shortcuts', label: 'Movement keys', shortcut: '?', Icon: KeyboardIcon },
  { id: 'copy', label: 'Copy LaTeX', shortcut: 'Cmd C', Icon: CopyIcon },
  { id: 'empty', label: 'Empty cell', Icon: CellEmptyIcon },
  { id: 'focused', label: 'Focused cell', Icon: CellFocusedIcon },
  { id: 'editing', label: 'Editing source', shortcut: 'Enter', Icon: CellEditingIcon },
  { id: 'selected', label: 'Selected cell', Icon: CellSelectedIcon },
  { id: 'computing', label: 'Computing', Icon: CellComputingIcon },
  { id: 'error', label: 'Cell error', Icon: CellErrorIcon },
  { id: 'send', label: 'Send message', shortcut: 'Enter', Icon: SendIcon },
  { id: 'stop', label: 'Stop drafting', shortcut: 'Esc', Icon: StopIcon },
  { id: 'delete', label: 'Delete cell', shortcut: 'Del', Icon: DeleteIcon },
]

const liveCellStates: readonly LiveCellStateSample[] = [
  {
    id: 'empty',
    cellId: 'state-cell-empty',
    label: 'Empty',
    detail: 'Type / inside the empty field to open the expression command menu.',
    initialLatex: '',
    Icon: CellEmptyIcon,
  },
  {
    id: 'focused',
    cellId: 'state-cell-focused',
    label: 'Focused',
    detail: 'Cell frame holds focus; arrow keys step structurally into numerators and limits.',
    initialLatex: '\\int_{0}^{\\infty} e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}',
    Icon: CellFocusedIcon,
  },
  {
    id: 'editing',
    cellId: 'state-cell-editing',
    label: 'Editing',
    detail: 'Active expression in progress with structural cursor navigation enabled.',
    initialLatex: '\\nabla \\mathcal{L}(\\theta) = \\frac{2}{N} X^\\top (X\\theta - y) + 2\\lambda \\theta',
    Icon: CellEditingIcon,
  },
  {
    id: 'selected',
    cellId: 'state-cell-selected',
    label: 'Selected',
    detail: 'Included in multi-cell selection or queued to attach to chat (Cmd L).',
    initialLatex: '\\sum_{k=1}^{n} k^2 = \\frac{n(n+1)(2n+1)}{6}',
    Icon: CellSelectedIcon,
  },
  {
    id: 'computing',
    cellId: 'state-cell-computing',
    label: 'Computing',
    detail: 'Symbolic solver evaluating the closed-form limit while the formula stays editable.',
    initialLatex: '\\lim_{n \\to \\infty} \\left(1 + \\frac{z}{n}\\right)^n',
    diagnostic: 'Evaluating symbolic limit…',
    Icon: CellComputingIcon,
  },
  {
    id: 'error',
    cellId: 'state-cell-error',
    label: 'Error',
    detail: 'Evaluation reported a domain singularity; the MathLive formula remains intact to fix.',
    initialLatex: '\\int_{-1}^{1} \\frac{1}{x^2}\\,dx',
    diagnostic: 'Divergent integral: non-integrable singularity at x = 0 in [−1, 1].',
    Icon: CellErrorIcon,
  },
]

/** Render the shared 16px Lucide icon set as compact hoverable buttons with tooltips and shortcuts. */
export function IconSet() {
  /** Render one icon button wrapped in its tooltip. */
  function renderIconSample(sample: IconSample) {
    const SampleIcon = sample.Icon
    return (
      <IconTooltip key={sample.id} label={sample.label} shortcut={sample.shortcut}>
        <button type="button" className="primitive-icon-button" aria-label={sample.label}>
          <SampleIcon />
        </button>
      </IconTooltip>
    )
  }

  return <div className="notebook-icon-grid">{iconSamples.map(renderIconSample)}</div>
}

/** Render each notebook cell state—empty, focused, editing, selected, computing, and error—around a real editable `LatexCell`. */
export function CellStates() {
  const [lastEdited, setLastEdited] = useState<string | null>(null)

  /** Record edits made inside any of the live MathLive state cells. */
  function recordCellEdit(cellId: string, latex: string) {
    const trimmed = latex.trim()
    setLastEdited(`${cellId}: ${trimmed ? trimmed : '(empty)'}`)
  }

  const handleLatexChange = useCallback(recordCellEdit, [])

  /** Render one headerless cell-state row containing a quiet gutter icon with a tooltip and a live `LatexCell`. */
  function renderLiveStateCell(state: LiveCellStateSample) {
    const StateIcon = state.Icon
    const tooltipText = state.diagnostic === undefined ? `${state.label} — ${state.detail}` : `${state.label} — ${state.diagnostic}`
    return (
      <div className={`notebook-live-cell notebook-state-${state.id}`} key={state.id}>
        <IconTooltip label={tooltipText}>
          <button type="button" className="notebook-cell-gutter" aria-label={`${state.label} cell state`}>
            <StateIcon />
          </button>
        </IconTooltip>
        <div className="notebook-live-cell-body">
          <LatexCell cellId={state.cellId} initialLatex={state.initialLatex} onLatexChange={handleLatexChange} />
        </div>
      </div>
    )
  }

  return (
    <div className="notebook-state-list notebook-wide">
      {liveCellStates.map(renderLiveStateCell)}
      {lastEdited === null ? null : <p className="primitive-status">Edited live LaTeX ({lastEdited})</p>}
    </div>
  )
}

/** Show ghost text inside a math cell and a Markdown cell, with an inline icon button to accept the completion. */
export function InlineSuggestion() {
  const [accepted, setAccepted] = useState(false)

  /** Replace the math ghost text with the completed word. */
  function acceptSuggestion() {
    setAccepted(true)
  }

  const status = accepted ? 'Accepted the suggestion.' : 'Tab accepts the ghost text. Escape dismisses it.'

  return (
    <div className="notebook-stack">
      <div className="notebook-suggestion" aria-label="Math cell with an inline suggestion">
        <MathIcon />
        <span className="notebook-suggestion-line">
          <InlineLatex latex={accepted ? '\\int_0^1 x^2 e^{-x}\\,dx' : '\\int_0^1 x^2'} />
          {accepted ? null : (
            <span className="notebook-suggestion-ghost">
              {' '}
              <InlineLatex latex="e^{-x}\,dx" />
            </span>
          )}
        </span>
        <IconTooltip label="Accept math suggestion" shortcut="Tab">
          <button type="button" className="primitive-icon-button primitive-icon-primary" aria-label="Accept math suggestion" onClick={acceptSuggestion}>
            <AcceptIcon />
          </button>
        </IconTooltip>
      </div>
      <div className="notebook-suggestion notebook-suggestion-note" aria-label="Markdown cell with an inline suggestion">
        <MarkdownIcon />
        <span className="notebook-suggestion-line">
          <span className="notebook-suggestion-typed">
            Since <InlineLatex latex="\lambda > 0" />, the Hessian{' '}
          </span>
          <span className="notebook-suggestion-ghost">is strictly positive definite.</span>
        </span>
      </div>
      <p className="primitive-status">{status}</p>
    </div>
  )
}

/** Sample the actions the notebook will register. Choosing one records its name. The shortcut text is not bound. */
const paletteActions: readonly CommandPaletteAction[] = [
  { id: 'focus-first', label: 'Focus first cell', shortcut: '⌘↑', keywords: ['top', 'start'] },
  { id: 'focus-last', label: 'Focus last cell', shortcut: '⌘↓', keywords: ['bottom', 'end'] },
  { id: 'focus-index', label: 'Focus cell by index', keywords: ['go to', 'number'] },
  { id: 'create-below', label: 'Create cell below', keywords: ['add', 'insert', 'new'] },
  { id: 'create-above', label: 'Create cell above', keywords: ['add', 'insert', 'new'] },
  { id: 'create-and-focus', label: 'Create cell and focus it', keywords: ['add', 'new'] },
  { id: 'delete-current', label: 'Delete current cell', keywords: ['remove'] },
]

/** Open the command palette and record which sample action was chosen. The notebook cells on this page stay where they are. */
export function CommandPaletteSpecimen() {
  const [open, setOpen] = useState(false)
  const [lastAction, setLastAction] = useState('None yet')

  /** Show the palette. */
  function openPalette() {
    setOpen(true)
  }

  /** Hide the palette without running an action. */
  function closePalette() {
    setOpen(false)
  }

  /** Record the chosen action and close the palette. */
  function runAction(action: CommandPaletteAction) {
    setLastAction(action.label)
    setOpen(false)
  }

  return (
    <div className="notebook-stack">
      <Button variant="quiet" onClick={openPalette}>
        Open command palette
      </Button>
      <p className="primitive-status">Last action: {lastAction}</p>
      <CommandPaletteView actions={paletteActions} open={open} onClose={closePalette} onRun={runAction} />
    </div>
  )
}

/** Toggle speech to text from a compact microphone icon button with a tooltip. */
export function SpeechInput() {
  const [listening, setListening] = useState(false)

  /** Switch between idle and listening. */
  function toggleListening() {
    setListening(listening === false)
  }

  const className = listening ? 'primitive-icon-button notebook-speech-live' : 'primitive-icon-button'
  const label = listening ? 'Stop dictation' : 'Dictate into focused cell'
  const status = listening ? 'Listening. Spoken math ("integral from zero to one") converts to LaTeX.' : 'Speech to text is off.'

  return (
    <div className="notebook-stack">
      <div className="primitive-bar">
        <IconTooltip label={label} shortcut="Cmd Shift V">
          <button type="button" className={className} aria-pressed={listening} aria-label={label} onClick={toggleListening}>
            <MicrophoneIcon />
          </button>
        </IconTooltip>
        <span className="notebook-inline-status">{status}</span>
      </div>
    </div>
  )
}
