/**
 * Render result and review cards for the notebook agent's tool calls: symbolic CAS, step verification, cell patch diffs, Python sandbox runs, notebook search, and reference lookup.
 *
 * @file
 */

import { useState } from 'react'
import type { MouseEvent } from 'react'
import { Collapsible } from '@base-ui/react/collapsible'
import {
  CellComputingIcon,
  CellPatchIcon,
  CellSelectedIcon,
  CloseIcon,
  CopyIcon,
  DisclosureChevronIcon,
  JumpToCellIcon,
  MarkdownIcon,
  MathIcon,
  PlusIcon,
  PythonSandboxIcon,
  ReferenceLookupIcon,
  SearchIcon,
  StopIcon,
  SymbolicComputeIcon,
  VerifyStepIcon,
} from '#/component-library/icons/folio-icons.tsx'
import { ChatMarkdown, InlineLatex } from './chat-math.tsx'
import { IconTooltip } from './icon-tooltip.tsx'

/** Track whether a proposed cell patch is waiting for review, applied, or discarded. */
type PatchDecision = 'pending' | 'applied' | 'discarded'

/** Describe one notebook cell matched by `search_notebook`. */
interface NotebookMatchRow {
  cellLabel: string
  role: string
  excerpt: string
}

const notebookMatches: readonly NotebookMatchRow[] = [
  { cellLabel: 'Cell 1', role: 'Assumptions', excerpt: '$X \\in \\mathbb{R}^{N \\times d}$, regularization $\\lambda > 0$' },
  { cellLabel: 'Cell 4', role: 'Objective', excerpt: '$\\mathcal{L}(\\theta) = \\frac{1}{N}\\|y - X\\theta\\|_2^2 + \\lambda \\|\\theta\\|_2^2$' },
  { cellLabel: 'Cell 6', role: 'Stationary point', excerpt: '$\\nabla \\mathcal{L}(\\theta^\\star) = 0 \\implies (X^\\top X + N\\lambda I)\\theta^\\star = X^\\top y$' },
]

/** Render the six notebook-native agent tool call cards and their interactive states. */
export function AgentToolCards() {
  const [patchDecision, setPatchDecision] = useState<PatchDecision>('pending')
  const [status, setStatus] = useState('None yet')

  /** Record a tool-card action so clicking any icon or pill updates the status line. */
  function recordAction(event: MouseEvent<HTMLButtonElement>) {
    const nextAction = event.currentTarget.dataset.action
    if (nextAction) setStatus(nextAction)
  }

  /** Accept the proposed cell edit. */
  function applyPatch() {
    setPatchDecision('applied')
    setStatus('Applied proposed LaTeX patch to Cell 5.')
  }

  /** Reject the proposed cell edit. */
  function discardPatch() {
    setPatchDecision('discarded')
    setStatus('Discarded proposed patch for Cell 5.')
  }

  /** Restore the cell-patch card back to its reviewable state. */
  function resetPatch() {
    setPatchDecision('pending')
    setStatus('Reset Cell 5 patch to awaiting review.')
  }

  /** Render one matched cell row inside the `search_notebook` result card. */
  function renderMatchRow(match: NotebookMatchRow) {
    return (
      <div className="tool-match-row" key={match.cellLabel}>
        <span className="tool-match-cell">
          <strong>{match.cellLabel}</strong> · {match.role}
        </span>
        <ChatMarkdown content={match.excerpt} className="tool-match-excerpt" />
        <IconTooltip label={`Jump to ${match.cellLabel}`}>
          <button type="button" className="primitive-icon-button primitive-icon-quiet" data-action={`Jumped to ${match.cellLabel}`} aria-label={`Jump to ${match.cellLabel}`} onClick={recordAction}>
            <JumpToCellIcon />
          </button>
        </IconTooltip>
      </div>
    )
  }

  return (
    <div className="tool-card-stack">
      {/* 1. Symbolic CAS evaluation */}
      <article className="tool-card" aria-label="Symbolic computation tool result">
        <header className="tool-card-header">
          <span className="tool-card-title">
            <SymbolicComputeIcon />
            <code>evaluate_symbolic</code>
            <span className="tool-badge tool-badge-done">18 ms</span>
          </span>
          <div className="tool-card-actions">
            <IconTooltip label="Insert result as math cell" shortcut="Opt Enter">
              <button type="button" className="primitive-icon-button primitive-icon-quiet" data-action="Inserted 2 − 5/e as math cell" aria-label="Insert result as math cell" onClick={recordAction}>
                <MathIcon />
              </button>
            </IconTooltip>
            <IconTooltip label="Copy LaTeX">
              <button type="button" className="primitive-icon-button primitive-icon-quiet" data-action="Copied 2 - \\frac{5}{e}" aria-label="Copy result LaTeX" onClick={recordAction}>
                <CopyIcon />
              </button>
            </IconTooltip>
          </div>
        </header>
        <div className="tool-cas-body">
          <div className="tool-cas-equation">
            <InlineLatex latex="\int_0^1 x^2 e^{-x}\,dx \;=\; 2 - \frac{5}{e}" display />
          </div>
          <div className="tool-meta-strip">
            <span>Exact symbolic · SymPy</span>
            <span>
              Numeric check: <InlineLatex latex="\approx 0.160602794" />
            </span>
          </div>
        </div>
      </article>

      {/* 2. Algebraic / proof step verification */}
      <article className="tool-card tool-card-warning" aria-label="Step verification tool result">
        <header className="tool-card-header">
          <span className="tool-card-title">
            <VerifyStepIcon />
            <code>verify_step</code>
            <span className="tool-badge tool-badge-warn">Domain constraint · Cell 4 → Cell 5</span>
          </span>
          <button type="button" className="notebook-chip" data-action="Added assumption x ≥ 1 to Cell 1" onClick={recordAction}>
            <PlusIcon /> Add <InlineLatex latex="x \ge 1" /> to Cell 1
          </button>
        </header>
        <div className="tool-step-body">
          <ChatMarkdown content="Checked $\sqrt{(x - 1)^2} = x - 1$. Holds if and only if $x \ge 1$; fails at counterexample $x = 0$ ($1 \neq -1$)." />
        </div>
      </article>

      {/* 3. Proposed cell edit / LaTeX diff */}
      <article className={`tool-card${patchDecision === 'applied' ? ' tool-card-applied' : ''}`} aria-label="Proposed cell edit tool card">
        <header className="tool-card-header">
          <span className="tool-card-title">
            <CellPatchIcon />
            <code>propose_cell_edit</code>
            <span className="tool-badge">Cell 5 · {patchDecision === 'pending' ? 'Awaiting review' : patchDecision === 'applied' ? 'Applied' : 'Discarded'}</span>
          </span>
          <div className="tool-card-actions">
            {patchDecision === 'pending' ? (
              <>
                <IconTooltip label="Apply patch to Cell 5" shortcut="Enter">
                  <button type="button" className="primitive-icon-button primitive-icon-primary" aria-label="Apply patch to Cell 5" onClick={applyPatch}>
                    <CellSelectedIcon />
                  </button>
                </IconTooltip>
                <IconTooltip label="Discard patch" shortcut="Esc">
                  <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label="Discard patch" onClick={discardPatch}>
                    <CloseIcon />
                  </button>
                </IconTooltip>
              </>
            ) : (
              <button type="button" className="notebook-chip" onClick={resetPatch}>
                Undo
              </button>
            )}
          </div>
        </header>
        <div className="tool-diff-grid">
          <div className="tool-diff-line tool-diff-remove">
            <span className="tool-diff-sign">−</span>
            <InlineLatex latex="\nabla^2 \mathcal{L}(\theta) = \frac{2}{N}\sum_{i=1}^{N} x_i x_i^\top + 2\lambda I" />
          </div>
          <div className="tool-diff-line tool-diff-add">
            <span className="tool-diff-sign">+</span>
            <InlineLatex latex="\nabla^2 \mathcal{L}(\theta) = \frac{2}{N}X^\top X + 2\lambda I \succeq 2\lambda I \succ 0" />
          </div>
        </div>
        <Collapsible.Root>
          <Collapsible.Trigger className="tool-disclosure-trigger">
            <DisclosureChevronIcon /> View LaTeX source diff
          </Collapsible.Trigger>
          <Collapsible.Panel className="tool-code-panel">
            <pre className="context-preview-pre">{`- \\nabla^2 \\mathcal{L}(\\theta) = \\frac{2}{N}\\sum_{i=1}^{N} x_i x_i^\\top + 2\\lambda I\n+ \\nabla^2 \\mathcal{L}(\\theta) = \\frac{2}{N}X^\\top X + 2\\lambda I \\succeq 2\\lambda I \\succ 0`}</pre>
          </Collapsible.Panel>
        </Collapsible.Root>
      </article>

      {/* 4. Numeric Python sandbox */}
      <article className="tool-card" aria-label="Python sandbox tool result">
        <header className="tool-card-header">
          <span className="tool-card-title">
            <PythonSandboxIcon />
            <code>run_python</code>
            <span className="tool-badge tool-badge-done">Exit 0 · 42 ms</span>
          </span>
          <IconTooltip label="Copy stdout">
            <button type="button" className="primitive-icon-button primitive-icon-quiet" data-action="Copied sandbox stdout" aria-label="Copy sandbox stdout" onClick={recordAction}>
              <CopyIcon />
            </button>
          </IconTooltip>
        </header>
        <div className="tool-sandbox-summary">
          <ChatMarkdown content="Verified Hessian spectrum for $N = 200, d = 12, \lambda = 0.1$: $\lambda_{\min} = 0.2004 > 0$, condition number $\kappa = 14.82$." />
        </div>
        <Collapsible.Root>
          <Collapsible.Trigger className="tool-disclosure-trigger">
            <DisclosureChevronIcon /> Inspect Python script & stdout
          </Collapsible.Trigger>
          <Collapsible.Panel className="tool-code-panel">
            <pre className="context-preview-pre">{`H = (2 / N) * (X.T @ X) + 2 * lam * np.eye(d)\neigs = np.linalg.eigvalsh(H)\nprint(f"min_eig={eigs[0]:.4f}, max_eig={eigs[-1]:.4f}, cond={eigs[-1]/eigs[0]:.2f}")\n# -> min_eig=0.2004, max_eig=2.9699, cond=14.82`}</pre>
          </Collapsible.Panel>
        </Collapsible.Root>
      </article>

      {/* 5. Notebook symbol / cell search */}
      <article className="tool-card" aria-label="Notebook search tool result">
        <header className="tool-card-header">
          <span className="tool-card-title">
            <SearchIcon />
            <code>search_notebook</code>
            <span className="tool-badge">
              Query: <InlineLatex latex="\theta, \lambda" /> · 3 cells
            </span>
          </span>
        </header>
        <div className="tool-match-list">{notebookMatches.map(renderMatchRow)}</div>
      </article>

      {/* 6. Theorem / PDF reference lookup + live running tool row */}
      <article className="tool-card" aria-label="Reference lookup tool result">
        <header className="tool-card-header">
          <span className="tool-card-title">
            <ReferenceLookupIcon />
            <code>lookup_reference</code>
            <span className="tool-badge">problem-set-4.pdf · Weyl’s Inequality</span>
          </span>
          <IconTooltip label="Insert citation into Markdown">
            <button type="button" className="primitive-icon-button primitive-icon-quiet" data-action="Inserted Weyl's Inequality citation" aria-label="Insert citation into Markdown" onClick={recordAction}>
              <MarkdownIcon />
            </button>
          </IconTooltip>
        </header>
        <div className="tool-step-body">
          <ChatMarkdown content="For symmetric $A = \frac{2}{N}X^\top X \succeq 0$ and perturbation $2\lambda I$, $\lambda_k(A + 2\lambda I) = \lambda_k(A) + 2\lambda \ge 2\lambda > 0$." />
        </div>
      </article>

      {/* Active streaming tool call indicator */}
      <div className="tool-running-bar" role="status">
        <span className="tool-card-title">
          <CellComputingIcon />
          <code>evaluate_symbolic</code>
          <span className="type-caption">
            Checking asymptotic limit as <InlineLatex latex="\lambda \to 0^+" />…
          </span>
        </span>
        <IconTooltip label="Cancel tool call" shortcut="Esc">
          <button type="button" className="primitive-icon-button primitive-icon-quiet" data-action="Stopped running tool call" aria-label="Cancel tool call" onClick={recordAction}>
            <StopIcon />
          </button>
        </IconTooltip>
      </div>

      <p className="primitive-status">Last tool action: {status}</p>
    </div>
  )
}
