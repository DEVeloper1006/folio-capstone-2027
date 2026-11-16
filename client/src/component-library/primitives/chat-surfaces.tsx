/**
 * Show two working design-page chats: a sidebar docked beside a notebook page, and a full-screen assistant. Both threads accept typed messages and suggestion chips, then answer with the same mock reply. Nothing here calls a model or changes the notebook.
 *
 * @file
 */

import { useEffect, useRef, useState } from 'react'
import type { FormEvent, MouseEvent, ReactNode } from 'react'
import { MarkdownMathField } from '#/component-library/markdown-math-field.tsx'
import { AssistantSparklesIcon, CellComputingIcon, CellPatchIcon, CloseIcon, CopyIcon, MarkdownIcon, MathIcon, MicrophoneIcon, SendIcon, StopIcon, SymbolicComputeIcon, VerifyStepIcon } from '#/component-library/icons/folio-icons.tsx'
import type { ContextAttachment } from './chat-context-specimens.tsx'
import { ContextAttachmentChip, sampleContextCatalog } from './chat-context-specimens.tsx'
import { ChatMarkdown, InlineLatex } from './chat-math.tsx'
import { IconTooltip } from './icon-tooltip.tsx'

/** One message already in a mock thread, including any context pills that were attached when it was sent. */
interface ChatTurn {
  id: string
  role: 'user' | 'assistant'
  content: string
  attachments: readonly ContextAttachment[]
}

/** A short prompt the composer can send without typing. The label is the chip; the prompt is the message that enters the thread. */
interface SuggestionPrompt {
  id: string
  label: string
  prompt: string
  Icon: () => ReactNode
}

/** A quiet notebook cell drawn beside the sidebar chat so the dock has a page to sit against. */
interface StubCell {
  id: string
  content: string
}

/** The draft, thread, and actions shared by the sidebar and full-screen mock chats. */
interface MockChat {
  turns: readonly ChatTurn[]
  draft: string
  attachments: readonly ContextAttachment[]
  listening: boolean
  drafting: boolean
  notice: string
  updateDraft: (value: string) => void
  sendDraft: () => void
  sendSuggestion: (event: MouseEvent<HTMLButtonElement>) => void
  toggleListening: () => void
  removeAttachment: (id: string) => void
  stopDrafting: () => void
  rememberNotice: (event: MouseEvent<HTMLButtonElement>) => void
}

/** How long the mock assistant shows “Drafting a reply…” before the canned message appears. */
const mockReplyDelayMs = 480

/** Reply appended after every user message. The wording does not depend on what was asked. */
const cannedAssistantReply = [
  'For every $\\lambda > 0$, the Hessian of the ridge objective stays positive definite:',
  '',
  '$$\\frac{2}{N}X^\\top X + 2\\lambda I \\succ 0$$',
  '',
  'so the estimator',
  '',
  '$$\\hat{\\theta}_\\lambda = \\left(X^\\top X + N\\lambda I\\right)^{-1} X^\\top y$$',
  '',
  'is defined even when $X^\\top X$ is singular.',
].join('\n')

const openingTurns: readonly ChatTurn[] = [
  {
    id: 'turn-user-1',
    role: 'user',
    content: 'Why did `np.linalg.cholesky` fail before adding $\\lambda \\|\\theta\\|_2^2$?',
    attachments: [sampleContextCatalog[3]],
  },
  {
    id: 'turn-assistant-1',
    role: 'assistant',
    content: cannedAssistantReply,
    attachments: [],
  },
]

const suggestionPrompts: readonly SuggestionPrompt[] = [
  { id: 'gradient', label: 'Derive the gradient', prompt: 'Derive $\\nabla \\mathcal{L}(\\theta)$ step by step.', Icon: AssistantSparklesIcon },
  { id: 'cholesky', label: 'Cholesky failure', prompt: 'Why did `np.linalg.cholesky` fail on $X^\\top X$?', Icon: SymbolicComputeIcon },
  { id: 'patch', label: 'Patch Cell 4', prompt: 'Propose a patch for the estimator in Cell 4.', Icon: CellPatchIcon },
]

const initialComposerAttachments: readonly ContextAttachment[] = [sampleContextCatalog[0], sampleContextCatalog[2]]

const initialDraft = 'Does $\\kappa(H)$ blow up as $\\lambda \\to 0^+$?'

const stubCells: readonly StubCell[] = [
  { id: 'assumptions', content: 'Assume $X \\in \\mathbb{R}^{N \\times d}$ and $\\lambda > 0$.' },
  { id: 'loss', content: '$$\\mathcal{L}(\\theta) = \\frac{1}{N}\\|y - X\\theta\\|_2^2 + \\lambda \\|\\theta\\|_2^2$$' },
  { id: 'estimator', content: '$$\\hat{\\theta}_\\lambda = \\left(X^\\top X + N\\lambda I\\right)^{-1} X^\\top y$$' },
]

/** Own one mock assistant thread. Any non-empty send appends that text, waits, then appends the canned reply. A send during that wait is ignored. Stop cancels the pending reply and leaves the user message in the thread. */
function useMockChat(): MockChat {
  const [turns, setTurns] = useState<readonly ChatTurn[]>(openingTurns)
  const [draft, setDraft] = useState(initialDraft)
  const [attachments, setAttachments] = useState<readonly ContextAttachment[]>(initialComposerAttachments)
  const [listening, setListening] = useState(false)
  const [drafting, setDrafting] = useState(false)
  const [notice, setNotice] = useState('')
  const turnCount = useRef(openingTurns.length)
  const replyTimer = useRef<number | null>(null)

  /** Cancel the pending canned reply, if one is waiting. */
  function clearReplyTimer() {
    if (replyTimer.current === null) return
    window.clearTimeout(replyTimer.current)
    replyTimer.current = null
  }

  /** Drop a pending reply when this chat leaves the page. */
  function cancelReplyOnUnmount() {
    return clearReplyTimer
  }

  useEffect(cancelReplyOnUnmount, [])

  /** Build the next thread id. The counter lives in a ref so a repeated render does not reuse an id. */
  function nextTurnId(role: 'user' | 'assistant') {
    turnCount.current += 1
    return `turn-${role}-${turnCount.current}`
  }

  /** Append the canned assistant message and clear the drafting row. */
  function appendCannedReply() {
    replyTimer.current = null
    const assistantTurn: ChatTurn = { id: nextTurnId('assistant'), role: 'assistant', content: cannedAssistantReply, attachments: [] }
    /** Keep the existing thread and add the canned reply at the end. */
    function addAssistantTurn(current: readonly ChatTurn[]) {
      return [...current, assistantTurn]
    }
    setTurns(addAssistantTurn)
    setDrafting(false)
  }

  /** Append one user message and schedule the canned reply. Ignore blank text and ignore a send that arrives while a reply is already pending. Clearing the composer is for a typed send; a suggestion leaves the draft in place. */
  function commitMessage(content: string, sentAttachments: readonly ContextAttachment[], clearComposer: boolean) {
    const trimmed = content.trim()
    if (trimmed.length === 0 || drafting) return
    const userTurn: ChatTurn = { id: nextTurnId('user'), role: 'user', content: trimmed, attachments: sentAttachments }
    /** Keep the existing thread and add the message that was just sent. */
    function addUserTurn(current: readonly ChatTurn[]) {
      return [...current, userTurn]
    }
    setTurns(addUserTurn)
    if (clearComposer) {
      setDraft('')
      setAttachments([])
    }
    setDrafting(true)
    clearReplyTimer()
    replyTimer.current = window.setTimeout(appendCannedReply, mockReplyDelayMs)
  }

  /** Keep the typed draft. Expressions in it are stored as `$...$`, which the field shows rendered. */
  function updateDraft(next: string) {
    setDraft(next)
  }

  /** Send the current draft and its context pills, then clear the composer. */
  function sendDraft() {
    commitMessage(draft, attachments, true)
  }

  /** Send the suggestion named on the pressed chip. The draft and its pills stay in the composer. */
  function sendSuggestion(event: MouseEvent<HTMLButtonElement>) {
    const prompt = event.currentTarget.dataset.prompt
    if (prompt === undefined) return
    commitMessage(prompt, [], false)
  }

  /** Switch the composer microphone between idle and listening. Speech is not transcribed on this page. */
  function toggleListening() {
    setListening(listening === false)
  }

  /** Remove one context pill from the composer. Pills already sent stay on their message. */
  function removeAttachment(id: string) {
    /** Keep every composer pill except the one that was dismissed. */
    function keepOther(item: ContextAttachment) {
      return item.id !== id
    }
    setAttachments(attachments.filter(keepOther))
  }

  /** Cancel the pending canned reply. The user message that started it stays in the thread. */
  function stopDrafting() {
    clearReplyTimer()
    setDrafting(false)
  }

  /** Store the action named on an assistant message button, such as inserting the formula or copying it. */
  function rememberNotice(event: MouseEvent<HTMLButtonElement>) {
    const nextNotice = event.currentTarget.dataset.notice
    if (nextNotice === undefined) return
    setNotice(nextNotice)
  }

  return { turns, draft, attachments, listening, drafting, notice, updateDraft, sendDraft, sendSuggestion, toggleListening, removeAttachment, stopDrafting, rememberNotice }
}

/** Render the transcript, including the canned reply's verification card and the drafting row. */
function ChatThread({ turns, drafting, onNotice }: { turns: readonly ChatTurn[]; drafting: boolean; onNotice: (event: MouseEvent<HTMLButtonElement>) => void }) {
  const threadRef = useRef<HTMLDivElement>(null)

  /** Move the transcript's scroll position to its last row. */
  function scrollThreadToEnd() {
    const thread = threadRef.current
    if (thread === null) return
    thread.scrollTop = thread.scrollHeight
  }

  useEffect(scrollThreadToEnd, [turns, drafting])

  /** Render one context pill that was stored on a sent message. Sent pills cannot be removed. */
  function renderTurnAttachment(attachment: ContextAttachment) {
    return <ContextAttachmentChip key={attachment.id} attachment={attachment} />
  }

  /** Render one user or assistant message. */
  function renderTurn(turn: ChatTurn) {
    const roleClass = turn.role === 'user' ? 'notebook-chat-message notebook-chat-user' : 'notebook-chat-message notebook-chat-assistant'
    return (
      <article className={roleClass} key={turn.id}>
        {turn.attachments.length > 0 ? <div className="notebook-chat-message-chips">{turn.attachments.map(renderTurnAttachment)}</div> : null}
        <ChatMarkdown content={turn.content} />
        {turn.role === 'assistant' ? <AssistantReplyExtras onNotice={onNotice} /> : null}
      </article>
    )
  }

  return (
    <div className="chat-thread" role="log" aria-label="Assistant conversation" ref={threadRef}>
      {turns.map(renderTurn)}
      {drafting ? (
        <div className="notebook-chat-drafting" role="status">
          <CellComputingIcon />
          Drafting a reply…
        </div>
      ) : null}
    </div>
  )
}

/** Render the verification card and insert actions that follow every canned assistant reply. */
function AssistantReplyExtras({ onNotice }: { onNotice: (event: MouseEvent<HTMLButtonElement>) => void }) {
  return (
    <>
      <div className="chat-inline-tool">
        <span className="tool-card-title">
          <VerifyStepIcon />
          <code>verify_step</code>
          <span className="tool-badge tool-badge-done">Verified · 12 ms</span>
        </span>
        <InlineLatex latex="\frac{2}{N}X^\top X + 2\lambda I \succ 0" />
      </div>
      <div className="notebook-chat-actions">
        <IconTooltip label="Insert formula as math cell" shortcut="Opt Enter">
          <button type="button" className="primitive-icon-button primitive-icon-quiet" data-notice="Inserted the ridge estimator as a math cell." aria-label="Insert formula as math cell" onClick={onNotice}>
            <MathIcon />
          </button>
        </IconTooltip>
        <IconTooltip label="Insert explanation as Markdown">
          <button type="button" className="primitive-icon-button primitive-icon-quiet" data-notice="Inserted the explanation as Markdown." aria-label="Insert explanation as Markdown" onClick={onNotice}>
            <MarkdownIcon />
          </button>
        </IconTooltip>
        <IconTooltip label="Copy reply">
          <button type="button" className="primitive-icon-button primitive-icon-quiet" data-notice="Copied the reply." aria-label="Copy reply" onClick={onNotice}>
            <CopyIcon />
          </button>
        </IconTooltip>
      </div>
    </>
  )
}

/** Render the suggestion chips above the composer. A chip sends its prompt through the same path as a typed message. */
function ChatSuggestions({ drafting, onSuggest }: { drafting: boolean; onSuggest: (event: MouseEvent<HTMLButtonElement>) => void }) {
  const chipClass = drafting ? 'notebook-chip chat-suggestion-waiting' : 'notebook-chip'

  /** Render one suggestion chip. */
  function renderSuggestion(suggestion: SuggestionPrompt) {
    const SuggestionIcon = suggestion.Icon
    return (
      <button key={suggestion.id} type="button" className={chipClass} data-prompt={suggestion.prompt} onClick={onSuggest}>
        <SuggestionIcon />
        {suggestion.label}
      </button>
    )
  }

  return (
    <div className="chat-suggestions" role="group" aria-label="Suggested questions">
      {suggestionPrompts.map(renderSuggestion)}
    </div>
  )
}

/** Render the composer: context pills, a markdown field that inserts math with `$`, and dictate, stop, and send. */
function ChatComposer({ chat }: { chat: MockChat }) {
  const microphoneClass = chat.listening ? 'primitive-icon-button notebook-speech-live' : 'primitive-icon-button primitive-icon-quiet'
  const stopClass = chat.drafting ? 'primitive-icon-button primitive-icon-primary' : 'primitive-icon-button primitive-icon-quiet'
  const microphoneLabel = chat.listening ? 'Stop dictation' : 'Dictate prompt'
  const draftLabel = chat.listening ? 'Listening…' : 'Ask about this page'

  /** Render one composer pill. Dismissing it removes that pill from the next send only. */
  function renderComposerAttachment(attachment: ContextAttachment) {
    return <ContextAttachmentChip key={attachment.id} attachment={attachment} onRemove={chat.removeAttachment} />
  }

  /** Send the draft from the composer form and keep the page from reloading. */
  function submitComposer(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    chat.sendDraft()
  }

  return (
    <form className="notebook-composer" onSubmit={submitComposer}>
      {chat.attachments.length > 0 ? <div className="notebook-composer-context">{chat.attachments.map(renderComposerAttachment)}</div> : null}
      <MarkdownMathField className="notebook-composer-input" value={chat.draft} onChange={chat.updateDraft} label={draftLabel} placeholder={draftLabel} submitOnEnter onSubmit={chat.sendDraft} onEscape={chat.stopDrafting} />
      <div className="notebook-composer-footer">
        <span className="type-caption">$ inserts an expression · Enter sends</span>
        <div className="notebook-composer-actions">
          <IconTooltip label={microphoneLabel} shortcut="Cmd Shift V">
            <button type="button" className={microphoneClass} aria-pressed={chat.listening} aria-label={microphoneLabel} onClick={chat.toggleListening}>
              <MicrophoneIcon />
            </button>
          </IconTooltip>
          <IconTooltip label="Stop reply" shortcut="Esc">
            <button type="button" className={stopClass} aria-label="Stop reply" onClick={chat.stopDrafting}>
              <StopIcon />
            </button>
          </IconTooltip>
          <IconTooltip label="Send message" shortcut="Enter">
            <button type="submit" className="primitive-icon-button primitive-icon-primary" aria-label="Send message">
              <SendIcon />
            </button>
          </IconTooltip>
        </div>
      </div>
    </form>
  )
}

/** Stack the transcript, suggestions, and composer under a header supplied by the sidebar or full-screen frame. */
function ChatColumn({ chat, header }: { chat: MockChat; header: ReactNode }) {
  return (
    <div className="chat-column">
      {header}
      <ChatThread turns={chat.turns} drafting={chat.drafting} onNotice={chat.rememberNotice} />
      <div className="chat-column-dock">
        <ChatSuggestions drafting={chat.drafting} onSuggest={chat.sendSuggestion} />
        <ChatComposer chat={chat} />
      </div>
    </div>
  )
}

/** Show the assistant name and the latest insert or copy action. */
function ChatHeaderTitle({ notice }: { notice: string }) {
  return (
    <>
      <span className="chat-column-title">
        <AssistantSparklesIcon />
        Assistant
      </span>
      <span className="chat-column-notice">{notice}</span>
    </>
  )
}

/** Render the sidebar header, including the control that closes the dock. */
function SidebarChatHeader({ notice, onClose }: { notice: string; onClose: () => void }) {
  return (
    <header className="chat-column-header">
      <ChatHeaderTitle notice={notice} />
      <IconTooltip label="Close assistant" shortcut="Cmd J">
        <button type="button" className="primitive-icon-button primitive-icon-quiet" aria-label="Close assistant" onClick={onClose}>
          <CloseIcon />
        </button>
      </IconTooltip>
    </header>
  )
}

/** Render the full-screen bar with the page name on the left and the assistant on the right. */
function FullScreenChatHeader({ notice }: { notice: string }) {
  return (
    <header className="chat-column-header">
      <span className="chat-column-title">Folio</span>
      <span className="chat-column-notice">{notice}</span>
      <span className="chat-column-title">
        <AssistantSparklesIcon />
        Assistant
      </span>
    </header>
  )
}

/** Render the notebook page the sidebar sits beside. The open control appears only after the dock is closed. */
function SidebarNotebookStub({ sidebarOpen, onOpen }: { sidebarOpen: boolean; onOpen: () => void }) {
  /** Render one static cell on the stub page. */
  function renderStubCell(cell: StubCell) {
    return (
      <div className="chat-stub-cell" key={cell.id}>
        <ChatMarkdown content={cell.content} />
      </div>
    )
  }

  return (
    <div className="chat-notebook-stub">
      <div className="chat-stub-header">
        <div>
          <p className="chat-stub-kicker">Notebook</p>
          <p className="chat-stub-title">Ridge regression</p>
        </div>
        {sidebarOpen ? null : (
          <IconTooltip label="Ask assistant" shortcut="Cmd J">
            <button type="button" className="primitive-icon-button primitive-icon-primary" aria-label="Ask assistant" aria-expanded={false} onClick={onOpen}>
              <AssistantSparklesIcon />
            </button>
          </IconTooltip>
        )}
      </div>
      {stubCells.map(renderStubCell)}
    </div>
  )
}

/** Render a notebook page with an assistant docked on the right. Closing the dock keeps the thread and reopening restores it. */
export function SidebarChat() {
  const chat = useMockChat()
  const [sidebarOpen, setSidebarOpen] = useState(true)

  /** Hide the dock. The messages stay in this component, so reopening shows the same thread. */
  function closeSidebar() {
    setSidebarOpen(false)
  }

  /** Show the dock again. */
  function openSidebar() {
    setSidebarOpen(true)
  }

  const frameClass = sidebarOpen ? 'chat-frame chat-frame-sidebar' : 'chat-frame chat-frame-sidebar is-closed'

  return (
    <div className={frameClass}>
      <SidebarNotebookStub sidebarOpen={sidebarOpen} onOpen={openSidebar} />
      {sidebarOpen ? <ChatColumn chat={chat} header={<SidebarChatHeader notice={chat.notice} onClose={closeSidebar} />} /> : null}
    </div>
  )
}

/** Render the same mock assistant as the whole surface, with the transcript and composer centered in the frame. */
export function FullScreenChat() {
  const chat = useMockChat()
  return (
    <div className="chat-frame chat-frame-full">
      <ChatColumn chat={chat} header={<FullScreenChatHeader notice={chat.notice} />} />
    </div>
  )
}
