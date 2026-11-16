/**
 * Manage a cell's expression-command session. Contains backslash triggering, cancellable local search, variant navigation, saved editor selection, and template insertion.
 *
 * @file
 */

import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { KeyboardEvent as ReactKeyboardEvent } from 'react'
import type { MathfieldElement } from 'mathlive'
import { searchExpressionCommands } from './expression-command-search.ts'
import type { CommandMatch, SearchExpressionCommands } from './expression-command-search.ts'
import type { ExpressionCommand } from './expression-commands.ts'

/** Retain the editor and insertion range while the menu's text input owns focus. */
interface CommandSession {
  mathfield: MathfieldElement
  selection: MathfieldElement['selection']
  latex: string
}

/** Open Folio's expression menu anywhere in editable mathematics. The saved selection becomes the insertion or replacement range. */
function canOpenCommands(mathfield: MathfieldElement) {
  return !mathfield.readOnly && mathfield.mode === 'math'
}

/** Keep menu state local to one cell; opening and cancelling never edits its formula. Accept a replacement search provider without changing menu rendering. */
export function useExpressionCommands(searchCommands: SearchExpressionCommands = searchExpressionCommands) {
  const [session, setSession] = useState<CommandSession | null>(null)
  const [query, setQuery] = useState('')
  const [matches, setMatches] = useState<readonly CommandMatch[]>([])
  const [parent, setParent] = useState<ExpressionCommand>()
  const [activeIndex, setActiveIndex] = useState(0)
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading')
  const restoreFocusRef = useRef<MathfieldElement | null>(null)

  /** Restore editor focus after React removes the focused search input, preserving the selection chosen by cancellation or insertion. */
  function restoreEditorFocus() {
    const mathfield = restoreFocusRef.current
    if (session || !mathfield) return
    restoreFocusRef.current = null
    if (mathfield.isConnected) mathfield.focus()
  }
  useLayoutEffect(restoreEditorFocus, [session])

  /** Search the current query and ignore responses after a new query, dismissal, or unmount. */
  function searchQuery() {
    if (!session) return
    let cancelled = false
    /** Publish only results belonging to the current open query. */
    function receiveMatches(results: readonly CommandMatch[]) {
      if (cancelled) return
      setMatches(results)
      setStatus('ready')
    }
    /** Keep provider failures inside the menu so they cannot interrupt the editor. */
    function reportSearchFailure() {
      if (!cancelled) setStatus('error')
    }
    void searchCommands({ query }).then(receiveMatches, reportSearchFailure)
    /** Invalidate pending results without retaining a mounted-editor listener. */
    function cancelSearch() {
      cancelled = true
    }
    return cancelSearch
  }
  useEffect(searchQuery, [session, query, searchCommands])

  /** Close the menu and optionally restore the original selection if the formula is still unchanged. */
  function closeMenu(restoreFocus = true) {
    if (restoreFocus && session?.mathfield.isConnected && session.mathfield.value === session.latex) {
      session.mathfield.selection = session.selection
      restoreFocusRef.current = session.mathfield
    }
    setSession(null)
  }

  /** Consume an unmodified backslash before mathematical navigation, saving the selection without inserting query text. */
  function handleEditorKeyDown(mathfield: MathfieldElement, event: KeyboardEvent) {
    if (event.key !== '\\' || event.ctrlKey || event.metaKey || event.altKey || event.isComposing || !canOpenCommands(mathfield)) return false
    setQuery('')
    setMatches([])
    setParent(undefined)
    setActiveIndex(0)
    setStatus('loading')
    setSession({ mathfield, selection: structuredClone(mathfield.selection), latex: mathfield.value })
    return true
  }

  /** Start a new search at the root list, discarding the previous query's results immediately. */
  function updateQuery(text: string) {
    setQuery(text)
    setMatches([])
    setParent(undefined)
    setActiveIndex(0)
    setStatus('loading')
  }

  /** Replace the saved insertion range once, selecting the first placeholder and preserving MathLive undo. Reject stale sessions after external edits. */
  function insertCommand(command: ExpressionCommand) {
    if (!session?.mathfield.isConnected || session.mathfield.value !== session.latex) {
      closeMenu(false)
      return
    }
    const { mathfield, selection } = session
    restoreFocusRef.current = mathfield
    setSession(null)
    mathfield.selection = selection
    mathfield.insert(command.latex, { format: 'latex', mode: 'math', insertionMode: 'replaceSelection', selectionMode: 'placeholder' })
  }

  /** Display a group's direct variants without changing the query or modifying the editor. The group itself stays selectable at the top of that list. */
  function openVariants(command: ExpressionCommand) {
    if (!command.variants?.length) return
    setParent(command)
    setActiveIndex(1)
  }

  /** Return to search results with their parent entry selected when it is present. */
  function backToResults() {
    /** Locate the parent that opened this variant list. */
    function isParent(match: CommandMatch) {
      return match.command.id === parent?.id
    }
    setActiveIndex(Math.max(0, matches.findIndex(isParent)))
    setParent(undefined)
  }

  /** List the opened command, then each direct variant. The opened command is not stored as a variant of itself. */
  function variantResults(command: ExpressionCommand): CommandMatch[] {
    /** Attach the opened command so a variant can show where it belongs. */
    function variantMatch(variant: ExpressionCommand): CommandMatch {
      return { command: variant, parent: command }
    }
    return [{ command }, ...(command.variants?.map(variantMatch) ?? [])]
  }
  const results = parent ? variantResults(parent) : matches

  /** Route menu keys separately from mathematical navigation; preserve text composition and ordinary input editing. */
  function handleMenuKeyDown(event: ReactKeyboardEvent<HTMLInputElement>) {
    if (event.nativeEvent.isComposing || event.ctrlKey || event.metaKey || event.altKey) return
    const selected = results.at(activeIndex)
    if (event.key === 'Escape' || (event.key === ' ' && !query)) closeMenu()
    else if (event.key === 'Tab') {
      closeMenu(false)
      return
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') setActiveIndex((activeIndex + (event.key === 'ArrowDown' ? 1 : -1) + results.length) % Math.max(1, results.length))
    else if (event.key === 'ArrowRight' && selected?.command.variants?.length && selected.command.id !== parent?.id) openVariants(selected.command)
    else if (event.key === 'ArrowLeft' && parent) backToResults()
    else if (event.key === 'Enter') {
      if (selected) insertCommand(selected.command)
    } else return
    event.preventDefault()
  }

  return { isOpen: session !== null, query, results, parent, activeIndex, status, updateQuery, setActiveIndex, handleEditorKeyDown, handleMenuKeyDown, insertCommand, openVariants, backToResults, closeMenu }
}
