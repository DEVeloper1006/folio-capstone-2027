/**
 * Manage a cell's expression-command session. Contains backslash triggering, query-cached cancellable search, variant navigation, saved editor selection, and template insertion.
 *
 * @file
 */

import { useLayoutEffect, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import type { QueryFunctionContext } from '@tanstack/react-query'
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

const searchProviders = new WeakMap<SearchExpressionCommands, number>()
let nextSearchProvider = 0

/** Share searches between cells using the same provider, while isolating replacement providers with different results. */
function searchProviderKey(provider: SearchExpressionCommands) {
  let key = searchProviders.get(provider)
  if (key === undefined) {
    key = nextSearchProvider++
    searchProviders.set(provider, key)
  }
  return key
}

/** Keep insertion and menu interactions local to one cell. Query owns provider results and request status, keyed by provider identity and search text; inactive searches expire after five minutes. */
export function useExpressionCommands(searchCommands: SearchExpressionCommands = searchExpressionCommands) {
  const [matrixBuilder, setMatrixBuilder] = useState<'blank' | 'sparse' | null>(null)
  const [session, setSession] = useState<CommandSession | null>(null)
  const [query, setQuery] = useState('')
  const [parent, setParent] = useState<ExpressionCommand>()
  const [activeIndex, setActiveIndex] = useState(0)
  const restoreFocusRef = useRef<MathfieldElement | null>(null)

  /** Restore editor focus after React removes the focused search input, preserving the selection chosen by cancellation or insertion. */
  function restoreEditorFocus() {
    const mathfield = restoreFocusRef.current
    if (session || !mathfield) return
    restoreFocusRef.current = null
    if (mathfield.isConnected) mathfield.focus()
  }
  useLayoutEffect(restoreEditorFocus, [session])

  /** Pass Query's abort signal to the provider so obsolete requests can stop without updating the active results. */
  function searchQuery({ signal }: QueryFunctionContext) {
    return searchCommands({ query, signal })
  }
  const search = useQuery({
    queryKey: ['expression-commands', searchProviderKey(searchCommands), session ? query : null],
    queryFn: searchQuery,
    enabled: session !== null,
    staleTime: Infinity,
    gcTime: 5 * 60 * 1000,
    retry: false,
    networkMode: 'always',
  })
  const matches = search.data ?? []
  const status = search.isError ? 'error' : search.isSuccess ? 'ready' : 'loading'

  /** Close the menu and optionally restore the original selection if the formula is still unchanged. */
  function closeMenu(restoreFocus = true) {
    if (restoreFocus && session?.mathfield.isConnected && session.mathfield.value === session.latex) {
      session.mathfield.selection = session.selection
      restoreFocusRef.current = session.mathfield
    }
    setSession(null)
    setMatrixBuilder(null)
  }

  /** Consume an unmodified backslash before mathematical navigation, saving the selection without inserting query text. */
  function handleEditorKeyDown(mathfield: MathfieldElement, event: KeyboardEvent) {
    if (event.key !== '\\' || event.ctrlKey || event.metaKey || event.altKey || event.isComposing || !canOpenCommands(mathfield)) return false
    setQuery('')
    setParent(undefined)
    setActiveIndex(0)
    setSession({ mathfield, selection: structuredClone(mathfield.selection), latex: mathfield.value })
    return true
  }

  /** Start a new search at the root list, discarding the previous query's results immediately. */
  function updateQuery(text: string) {
    setQuery(text)
    setParent(undefined)
    setActiveIndex(0)
  }

  /** Replace the saved insertion range once, selecting the first placeholder and preserving MathLive undo. Reject stale sessions after external edits. */
  function insertCommand(command: ExpressionCommand) {
    if (!session?.mathfield.isConnected || session.mathfield.value !== session.latex) {
      closeMenu(false)
      return
    }
    if (command.id === 'matrix' || command.id === 'matrix-sparse') {
      setMatrixBuilder(command.id === 'matrix-sparse' ? 'sparse' : 'blank')
      return
    }
    setMatrixBuilder(null)
    const { mathfield, selection } = session
    restoreFocusRef.current = mathfield
    setSession(null)
    mathfield.selection = selection
    mathfield.insert(command.latex, { format: 'latex', mode: 'math', insertionMode: 'replaceSelection', selectionMode: 'placeholder' })
  }

  /** Insert the builder's validated template at the session's saved cursor. */
  function insertMatrix(latex: string) {
    insertCommand({ id: 'matrix-generated', label: 'Matrix', symbol: '[ ]', keywords: [], relevance: 0, latex })
  }
  /** Return to search without touching the formula. */
  function closeMatrixBuilder() {
    setMatrixBuilder(null)
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

  return { matrixBuilder, insertMatrix, closeMatrixBuilder, isOpen: session !== null, query, results, parent, activeIndex, status, updateQuery, setActiveIndex, handleEditorKeyDown, handleMenuKeyDown, insertCommand, openVariants, backToResults, closeMenu }
}
