/**
 * Render the expression search input, selectable results, and one-level variant list beneath a cell. Contains accessible combobox wiring, focus cleanup, and mouse interactions.
 *
 * @file
 */

import { useEffect, useId, useRef } from 'react'
import type { ChangeEvent, FocusEvent, MouseEvent } from 'react'
import type { useExpressionCommands } from '#/editor/use-expression-commands'
import type { CommandMatch } from '#/editor/expression-command-search'

/** Receive the local command session and its handlers without owning search or MathLive integration. */
interface ExpressionCommandMenuProps {
  menu: ReturnType<typeof useExpressionCommands>
}

/** Render a focused search box with arrow-key selection and independently insertable variants. Dismiss on focus leaving the menu without stealing focus back. */
export function ExpressionCommandMenu({ menu }: ExpressionCommandMenuProps) {
  const listId = useId()
  const inputRef = useRef<HTMLInputElement>(null)
  const activeResultRef = useRef<HTMLButtonElement>(null)

  /** Focus the query when a new command session opens. */
  function focusQuery() {
    inputRef.current?.focus()
  }
  useEffect(focusQuery, [])

  /** Keep keyboard selection visible when the results extend beyond the menu's scroll area. */
  function revealActiveResult() {
    activeResultRef.current?.scrollIntoView({ block: 'nearest' })
  }
  useEffect(revealActiveResult, [menu.activeIndex, menu.results])

  /** Pass typed query text to the replaceable search provider. */
  function handleQueryChange(event: ChangeEvent<HTMLInputElement>) {
    menu.updateQuery(event.target.value)
  }

  /** Dismiss only when focus moves outside this menu, including back into the mathfield. */
  function handleBlur(event: FocusEvent<HTMLDivElement>) {
    if (!event.currentTarget.contains(event.relatedTarget)) menu.closeMenu(false)
  }

  /** Preserve query focus while mouse actions select or insert a result. */
  function keepQueryFocus(event: MouseEvent) {
    event.preventDefault()
  }

  /** Restore the editor when the close button is activated. */
  function handleClose() {
    menu.closeMenu()
  }

  /** Render an insertable command and a separate variants button when children exist. */
  function renderResult(match: CommandMatch, index: number) {
    const { command, parent } = match
    const isActive = index === menu.activeIndex
    /** Insert the clicked command without requiring navigation through its parent. */
    function handleInsert() {
      menu.insertCommand(command)
    }
    /** Show this command's direct variants. */
    function handleVariants() {
      menu.openVariants(command)
    }
    /** Keep keyboard navigation aligned with the row under the pointer. */
    function handlePointerMove() {
      if (!isActive) menu.setActiveIndex(index)
    }
    return (
      <div className={`command-result${isActive ? ' is-active' : ''}`} key={command.id} onPointerMove={handlePointerMove} role="presentation">
        <button id={`${listId}-${command.id}`} ref={isActive ? activeResultRef : undefined} type="button" role="option" aria-selected={isActive} tabIndex={-1} onMouseDown={keepQueryFocus} onClick={handleInsert}>
          <span className="command-symbol" aria-hidden="true">
            {command.symbol}
          </span>
          <span>
            {command.label}
            {parent && <small>{parent.label}</small>}
          </span>
        </button>
        {command.variants?.length ? (
          <button className="command-variants" type="button" tabIndex={-1} aria-label={`Variants of ${command.label}`} onMouseDown={keepQueryFocus} onClick={handleVariants}>
            ›
          </button>
        ) : null}
      </div>
    )
  }

  const selected = menu.results.at(menu.activeIndex)
  return (
    <div className="command-menu" onBlur={handleBlur}>
      <div className="command-search">
        <span aria-hidden="true">/</span>
        <input
          ref={inputRef}
          aria-label="Search expressions"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded="true"
          aria-controls={listId}
          aria-activedescendant={selected ? `${listId}-${selected.command.id}` : undefined}
          autoComplete="off"
          value={menu.query}
          onChange={handleQueryChange}
          onKeyDown={menu.handleMenuKeyDown}
          placeholder="Search expressions…"
        />
        <button type="button" aria-label="Close expression menu" onClick={handleClose}>
          ×
        </button>
      </div>
      {menu.parent && (
        <button type="button" className="command-back" onMouseDown={keepQueryFocus} onClick={menu.backToResults}>
          ← {menu.parent.label}
        </button>
      )}
      <div id={listId} role="listbox" aria-label={menu.parent ? `${menu.parent.label} variants` : 'Expressions'} aria-busy={menu.status === 'loading'} className="command-results">
        {menu.results.map(renderResult)}
      </div>
      {!menu.results.length && <p role="status">{menu.status === 'loading' ? 'Searching…' : menu.status === 'error' ? 'Search unavailable. Try another query.' : 'No matching expressions.'}</p>}
      <p className="command-help">↑ ↓ select · → variants · ← back · Enter insert · Esc close</p>
    </div>
  )
}
