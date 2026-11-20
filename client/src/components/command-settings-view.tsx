/**
 * Render the keyboard shortcut table. Contains the command search and one row per command, with its keybinding, context, and source. The notebook supplies the commands and stores a recorded keybinding label. This view does not bind keys or run a command.
 *
 * @file
 */

import { useEffect, useState } from 'react'
import type { ChangeEvent } from 'react'
import { Button, TextField } from '#/component-library/index.ts'
import { editorCommandShortcut, editorCommandShortcutIsCustom, editorCommands } from '#/editor/commands/editor-commands.ts'
import type { EditorCommand } from '#/editor/commands/editor-commands.ts'
import { formatShortcut, shortcutKeys, shortcutBinding } from '#/editor/commands/shortcut-label.ts'

/** Receive the recorded shortcut labels and report a new label, a reset, or a request to open the palette. */
interface CommandSettingsViewProps {
  overrides: Readonly<Record<string, string>>
  paletteOpen: boolean
  lastCommandLabel?: string
  onShortcutChange: (commandId: string, shortcut: string, binding: string) => void
  onResetShortcut: (commandId: string) => void
  onOpenCommandPalette: () => void
}

/** Ignore a key that only names a modifier, so the shortcut waits for the key it modifies. */
function isModifierKey(key: string) {
  return key === 'Meta' || key === 'Control' || key === 'Alt' || key === 'Shift'
}

/** Keep a command when every word of the query appears in its label, id, context, or keywords. An empty query keeps every command. */
function commandMatches(command: EditorCommand, query: string) {
  if (!query) return true
  const terms = [command.label, command.id, command.when, ...command.keywords].join(' ').toLowerCase()
  /** Find this query word in the command's searchable text. */
  function containsWord(word: string) {
    return terms.includes(word)
  }
  return query.split(' ').every(containsWord)
}

/** Show the catalog in a shortcut table and let one row record a replacement keybinding label. Opening the palette uses the same labels. */
export function CommandSettingsView({ overrides, paletteOpen, onShortcutChange, onResetShortcut, onOpenCommandPalette }: CommandSettingsViewProps) {
  const [query, setQuery] = useState('')
  const [recordingId, setRecordingId] = useState<string | null>(null)
  const normalizedQuery = query.toLowerCase().trim().replace(/\s+/g, ' ')
  /** Keep the commands that match the current query. */
  function matchesQuery(command: EditorCommand) {
    return commandMatches(command, normalizedQuery)
  }
  const matches = editorCommands.filter(matchesQuery)

  /** Stop a recording when the palette opens, so its keys are not stored as a shortcut label. */
  function stopRecordingForPalette() {
    if (paletteOpen) setRecordingId(null)
  }
  useEffect(stopRecordingForPalette, [paletteOpen])

  /** Store the next key combination as the recording command's shortcut label. Unmodified Escape cancels, and unmodified Backspace or Delete clears the label. */
  function listenForShortcut() {
    if (recordingId === null || paletteOpen) return
    const commandId = recordingId

    /** Apply one key to the command that is waiting for a shortcut. */
    function handleKeyDown(event: KeyboardEvent) {
      if (event.isComposing || isModifierKey(event.key)) return
      event.preventDefault()
      event.stopPropagation()
      const unmodified = !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey
      if (event.key === 'Escape' && unmodified) {
        setRecordingId(null)
        return
      }
      const clear = unmodified && (event.key === 'Backspace' || event.key === 'Delete')
      onShortcutChange(commandId, clear ? '' : formatShortcut(event), clear ? '' : shortcutBinding(event))
      setRecordingId(null)
    }

    /** Remove the key listener when recording ends or the list unmounts. */
    function stopListening() {
      document.removeEventListener('keydown', handleKeyDown, true)
    }

    document.addEventListener('keydown', handleKeyDown, true)
    return stopListening
  }
  useEffect(listenForShortcut, [recordingId, paletteOpen, onShortcutChange])

  /** Store the typed query. */
  function handleQueryChange(event: ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
  }

  /** Close any recording and ask the notebook to show the palette. */
  function openPalette() {
    setRecordingId(null)
    onOpenCommandPalette()
  }

  /** Render one keycap from a shortcut label. The index keeps two identical marks distinct. */
  function renderKeycap(key: string, index: number) {
    return (
      <kbd key={`${key}-${index}`} className="command-keycap">
        {key}
      </kbd>
    )
  }

  /** Render one table row: the command name, its keycaps, the context label, and whether the keybinding is the catalog default. */
  function renderCommand(command: EditorCommand) {
    const shortcut = editorCommandShortcut(command, overrides)
    const isRecording = command.id === recordingId
    const isCustom = editorCommandShortcutIsCustom(command, overrides)
    const keys = shortcut ? shortcutKeys(shortcut) : []

    /** Wait for the next key combination, or cancel when this row is already waiting. */
    function beginRecording() {
      setRecordingId(isRecording ? null : command.id)
    }

    /** Restore the catalog shortcut label for this command. */
    function resetShortcut() {
      if (isRecording) setRecordingId(null)
      onResetShortcut(command.id)
    }

    return (
      <tr key={command.id} className={isRecording ? 'is-recording' : undefined} title={command.id}>
        <td className="command-settings-command">{command.label}</td>
        <td>
          <button type="button" className={isRecording ? 'command-settings-shortcut is-recording' : 'command-settings-shortcut'} aria-label={isRecording ? `Press a shortcut for ${command.label}` : `Keybinding for ${command.label}`} onClick={beginRecording}>
            {isRecording ? 'Press shortcut' : keys.length === 0 ? <span className="command-settings-unbound">—</span> : keys.map(renderKeycap)}
          </button>
        </td>
        <td className="command-settings-when">{command.when}</td>
        <td>
          <div className="command-settings-source">
            <span className={isCustom ? 'is-user' : undefined}>{isCustom ? 'User' : 'System'}</span>
            {isCustom ? (
              <Button variant="quiet" className="command-settings-reset" onClick={resetShortcut}>
                Reset
              </Button>
            ) : null}
          </div>
        </td>
      </tr>
    )
  }

  return (
    <div className="command-settings">
      <h2>Keyboard shortcuts</h2>
      <p className="command-settings-lead">Click a keybinding and press its new shortcut. Escape cancels; Backspace removes a binding.</p>
      <div className="command-settings-actions">
        <Button onClick={openPalette}>Open command palette</Button>
      </div>
      <TextField label="Search commands" value={query} onChange={handleQueryChange} placeholder="Name, id, or context" />
      {matches.length === 0 ? (
        <p className="command-settings-empty">No matching commands</p>
      ) : (
        <div className="command-settings-scroll">
          <table className="command-settings-table">
            <thead>
              <tr>
                <th scope="col">Command</th>
                <th scope="col">Keybinding</th>
                <th scope="col">When</th>
                <th scope="col">Source</th>
              </tr>
            </thead>
            <tbody>{matches.map(renderCommand)}</tbody>
          </table>
        </div>
      )}
    </div>
  )
}
