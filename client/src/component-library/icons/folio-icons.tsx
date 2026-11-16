/**
 * Re-export Folio's tree-shakeable Lucide icons sized to 16px for compact notebook chrome. Contains marks for formatting, cell states, context attachments, agent tool calls, menus, speech, inline suggestions, and chat actions.
 *
 * @file
 */

import {
  ArrowUp,
  AtSign,
  Bold,
  BookOpen,
  Braces,
  Calculator,
  Check,
  CheckCircle2,
  ChevronRight,
  ClipboardPaste,
  Code,
  Columns2,
  Copy,
  CornerDownLeft,
  CornerUpRight,
  Ellipsis,
  Eye,
  FileCode,
  FileText,
  GitCompare,
  Globe,
  Heading2,
  Italic,
  Keyboard,
  Link2,
  List,
  LoaderCircle,
  Maximize2,
  MessageSquarePlus,
  Mic,
  Minus,
  Paperclip,
  Pencil,
  Plus,
  Quote,
  Radical,
  Search,
  Sigma,
  SlidersHorizontal,
  Sparkles,
  Square,
  SquareDashed,
  Terminal,
  TextCursorInput,
  Trash2,
  TriangleAlert,
  X,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

/** Render a decorative 16px Lucide icon that inherits the surrounding control's text color. */
function renderCompactIcon(IconComponent: LucideIcon, className?: string) {
  const iconClass = className === undefined ? 'folio-icon' : `folio-icon ${className}`
  return <IconComponent className={iconClass} size={16} strokeWidth={1.75} aria-hidden="true" />
}

/** Mark the speech-to-text dictation toggle. */
export function MicrophoneIcon() {
  return renderCompactIcon(Mic)
}

/** Mark an inline ghost suggestion waiting in a cell. */
export function AutocompleteIcon() {
  return renderCompactIcon(TextCursorInput)
}

/** Mark a cell that has no source yet. */
export function CellEmptyIcon() {
  return renderCompactIcon(SquareDashed)
}

/** Mark a cell that has focus without an open source editor. */
export function CellFocusedIcon() {
  return renderCompactIcon(Square)
}

/** Mark a cell whose source is open for typing, or an edit action. */
export function CellEditingIcon() {
  return renderCompactIcon(Pencil)
}

/** Mark a selected cell or a completed choice. */
export function CellSelectedIcon() {
  return renderCompactIcon(Check)
}

/** Mark a cell or assistant reply that is still computing. */
export function CellComputingIcon() {
  return renderCompactIcon(LoaderCircle, 'folio-icon-spin')
}

/** Mark a cell whose source or evaluation failed. */
export function CellErrorIcon() {
  return renderCompactIcon(TriangleAlert)
}

/** Mark the control that sends the current chat draft. */
export function SendIcon() {
  return renderCompactIcon(ArrowUp)
}

/** Mark the control that stops a streaming reply. */
export function StopIcon() {
  return renderCompactIcon(Square)
}

/** Mark a mathematical expression or LaTeX insertion action. */
export function MathIcon() {
  return renderCompactIcon(Sigma)
}

/** Mark a square-root or display-math insertion action. */
export function DisplayMathIcon() {
  return renderCompactIcon(Radical)
}

/** Mark a Markdown note cell or prose insertion action. */
export function MarkdownIcon() {
  return renderCompactIcon(FileText)
}

/** Mark bold text formatting. */
export function BoldIcon() {
  return renderCompactIcon(Bold)
}

/** Mark italic text formatting. */
export function ItalicIcon() {
  return renderCompactIcon(Italic)
}

/** Mark inline or fenced code formatting. */
export function CodeIcon() {
  return renderCompactIcon(Code)
}

/** Mark a section heading mark in Markdown. */
export function HeadingIcon() {
  return renderCompactIcon(Heading2)
}

/** Mark a blockquote in Markdown. */
export function QuoteIcon() {
  return renderCompactIcon(Quote)
}

/** Mark a hyperlink in Markdown. */
export function LinkIcon() {
  return renderCompactIcon(Link2)
}

/** Mark a bulleted list in Markdown. */
export function ListIcon() {
  return renderCompactIcon(List)
}

/** Mark the rendered Markdown preview tab. */
export function PreviewIcon() {
  return renderCompactIcon(Eye)
}

/** Mark the raw Markdown source tab. */
export function SourceIcon() {
  return renderCompactIcon(FileCode)
}

/** Mark a narrow reading column width. */
export function RegularWidthIcon() {
  return renderCompactIcon(Columns2)
}

/** Mark a full-bleed page width. */
export function FullWidthIcon() {
  return renderCompactIcon(Maximize2)
}

/** Mark page display and layout preferences. */
export function SettingsIcon() {
  return renderCompactIcon(SlidersHorizontal)
}

/** Mark a cell or overflow action menu trigger. */
export function MoreActionsIcon() {
  return renderCompactIcon(Ellipsis)
}

/** Mark an add or increment action. */
export function PlusIcon() {
  return renderCompactIcon(Plus)
}

/** Mark a decrement action. */
export function MinusIcon() {
  return renderCompactIcon(Minus)
}

/** Mark expression or template search. */
export function SearchIcon() {
  return renderCompactIcon(Search)
}

/** Mark keyboard navigation hints and shortcut lists. */
export function KeyboardIcon() {
  return renderCompactIcon(Keyboard)
}

/** Mark a copy-to-clipboard action. */
export function CopyIcon() {
  return renderCompactIcon(Copy)
}

/** Mark a delete cell action. */
export function DeleteIcon() {
  return renderCompactIcon(Trash2)
}

/** Mark a dialog close or chip remove button. */
export function CloseIcon() {
  return renderCompactIcon(X)
}

/** Mark a collapsible disclosure chevron that rotates when open. */
export function DisclosureChevronIcon() {
  return renderCompactIcon(ChevronRight, 'primitive-chevron')
}

/** Mark an assistant prompt or AI follow-up suggestion. */
export function AssistantSparklesIcon() {
  return renderCompactIcon(Sparkles)
}

/** Mark a Tab/Enter inline completion acceptance action. */
export function AcceptIcon() {
  return renderCompactIcon(CornerDownLeft)
}

/** Mark the @ context-attachment trigger in the chat composer. */
export function AttachContextIcon() {
  return renderCompactIcon(AtSign)
}

/** Mark an attached PDF, image, or source file in chat context. */
export function FileAttachmentIcon() {
  return renderCompactIcon(Paperclip)
}

/** Mark a long pasted text or log snippet collapsed into a chat context pill. */
export function PasteSnippetIcon() {
  return renderCompactIcon(ClipboardPaste)
}

/** Mark an external URL, DOI, or paper link attached to chat. */
export function WebLinkIcon() {
  return renderCompactIcon(Globe)
}

/** Mark a syntactic LaTeX sub-expression selected inside a cell. */
export function SubExpressionIcon() {
  return renderCompactIcon(Braces)
}

/** Mark an action that sends a selected sub-expression or cell into the chat composer. */
export function AddToChatIcon() {
  return renderCompactIcon(MessageSquarePlus)
}

/** Mark a symbolic CAS evaluation tool call. */
export function SymbolicComputeIcon() {
  return renderCompactIcon(Calculator)
}

/** Mark an algebraic equivalence or proof-step verification tool call. */
export function VerifyStepIcon() {
  return renderCompactIcon(CheckCircle2)
}

/** Mark a proposed cell patch or before/after LaTeX diff card. */
export function CellPatchIcon() {
  return renderCompactIcon(GitCompare)
}

/** Mark a numeric Python sandbox execution tool call. */
export function PythonSandboxIcon() {
  return renderCompactIcon(Terminal)
}

/** Mark a theorem, textbook, or paper lookup tool call. */
export function ReferenceLookupIcon() {
  return renderCompactIcon(BookOpen)
}

/** Mark an action that jumps from a chat citation or tool match to its notebook cell. */
export function JumpToCellIcon() {
  return renderCompactIcon(CornerUpRight)
}
