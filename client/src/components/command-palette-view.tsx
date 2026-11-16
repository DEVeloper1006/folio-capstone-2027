/**
 * Render the notebook command palette. Contains the search field, the filtered action list, and keyboard selection. The notebook supplies the actions and runs the chosen one. This view does not register actions or listen for their shortcuts.
 *
 * @file
 */

import { useEffect, useId, useRef, useState } from 'react'
import type { ChangeEvent, KeyboardEvent, MouseEvent } from 'react'

/** Name one action the palette can search and run. The shortcut is display text; binding it is the caller's job. */
export interface CommandPaletteAction {
  id: string
  label: string
  shortcut?: string
  keywords?: readonly string[]
}

/** Receive the registered actions and report a run or a dismissal. The caller decides when the palette is open. */
interface CommandPaletteViewProps {
  actions: readonly CommandPaletteAction[]
  open: boolean
  onClose: () => void
  onRun: (action: CommandPaletteAction) => void
}

/** Fold case and surrounding space so a query matches a label or a keyword. */
function normalize(text: string) {
  return text.toLowerCase().trim().replace(/\s+/g, ' ')
}

/** Keep an action when every word of the query appears in its label, id, or keywords. An empty query keeps every action. */
function actionMatches(action: CommandPaletteAction, query: string) {
  if (!query) return true
  const terms = [action.label, action.id, ...(action.keywords ?? [])].map(normalize)
  const words = query.split(' ')
  /** Find this query word in one searchable term. */
  function containsWord(word: string) {
    /** Test one label, id, or keyword. */
    function contains(term: string) {
      return term.includes(word)
    }
    return terms.some(contains)
  }
  return words.every(containsWord)
}

/** Show a centered search list of actions. Arrow keys move the highlight, Enter runs it, and Escape or the backdrop closes the palette. */
export function CommandPaletteView({ actions, open, onClose, onRun }: CommandPaletteViewProps) {
  const listId = useId()
  const inputRef = useRef<HTMLInputElement>(null)
  const activeRef = useRef<HTMLButtonElement>(null)
  const [query, setQuery] = useState('')
  const [activeIndex, setActiveIndex] = useState(0)
  const normalizedQuery = normalize(query)
  /** Keep the actions that match the current query. */
  function matchesQuery(action: CommandPaletteAction) {
    return actionMatches(action, normalizedQuery)
  }
  const matches = actions.filter(matchesQuery)
  const selectedIndex = matches.length === 0 ? 0 : Math.min(activeIndex, matches.length - 1)

  /** Clear the previous search and focus the field each time the palette opens. */
  function prepareOpenedPalette() {
    if (!open) return
    setQuery('')
    setActiveIndex(0)
    inputRef.current?.focus()
  }
  useEffect(prepareOpenedPalette, [open])

  /** Keep the highlighted action inside the scrollable list. */
  function revealActiveAction() {
    activeRef.current?.scrollIntoView({ block: 'nearest' })
  }
  useEffect(revealActiveAction, [selectedIndex, matches.length, open])

  if (!open) return null

  /** Store the typed query and return the highlight to the first match. */
  function handleQueryChange(event: ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
    setActiveIndex(0)
  }

  /** Move through matches, run the highlighted action, or close the palette. */
  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === 'Escape') {
      event.preventDefault()
      onClose()
      return
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault()
      const direction = event.key === 'ArrowDown' ? 1 : -1
      /** Step the highlight and wrap at either end of the current matches. */
      function moveHighlight(index: number) {
        if (matches.length === 0) return 0
        return (Math.min(index, matches.length - 1) + direction + matches.length) % matches.length
      }
      setActiveIndex(moveHighlight)
      return
    }
    if (event.key !== 'Enter' || matches.length === 0) return
    event.preventDefault()
    onRun(matches[selectedIndex])
  }

  /** Close when the pointer lands on the dimmed backdrop rather than the panel. */
  function handleBackdropMouseDown(event: MouseEvent<HTMLDivElement>) {
    if (event.target === event.currentTarget) onClose()
  }

  /** Render one matching action, with its shortcut when the caller supplied one. */
  function renderAction(action: CommandPaletteAction, index: number) {
    const isActive = index === selectedIndex
    /** Run this action from a click. */
    function handleRun() {
      onRun(action)
    }
    /** Highlight the row under the pointer without moving focus out of the search field. */
    function handlePointerMove() {
      if (!isActive) setActiveIndex(index)
    }
    /** Keep the search field focused while the pointer selects a row. */
    function keepQueryFocus(event: MouseEvent) {
      event.preventDefault()
    }
    return (
      <button id={`${listId}-${action.id}`} key={action.id} ref={isActive ? activeRef : undefined} type="button" role="option" className={isActive ? 'is-active' : undefined} aria-selected={isActive} tabIndex={-1} onMouseDown={keepQueryFocus} onClick={handleRun} onPointerMove={handlePointerMove}>
        <span>{action.label}</span>
        {action.shortcut ? <kbd className="command-palette-shortcut">{action.shortcut}</kbd> : null}
      </button>
    )
  }

  return (
    <div className="command-palette-backdrop" onMouseDown={handleBackdropMouseDown}>
      <div className="command-palette" role="dialog" aria-modal="true" aria-label="Commands" onKeyDown={handleKeyDown}>
        <div className="command-palette-search">
          <input
            ref={inputRef}
            role="combobox"
            aria-autocomplete="list"
            aria-expanded={matches.length > 0}
            aria-controls={listId}
            aria-activedescendant={matches[selectedIndex] ? `${listId}-${matches[selectedIndex].id}` : undefined}
            aria-label="Search commands"
            placeholder="Search commands…"
            value={query}
            onChange={handleQueryChange}
          />
        </div>
        {matches.length === 0 ? (
          <p className="command-palette-empty">No matching commands</p>
        ) : (
          <div id={listId} className="command-palette-results" role="listbox" aria-label="Commands">
            {matches.map(renderAction)}
          </div>
        )}
      </div>
    </div>
  )
}
