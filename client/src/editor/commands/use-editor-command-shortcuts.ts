/**
 * Remember shortcut labels chosen in settings for this browser session. Contains the override map and the functions that write or clear one command's label. Cursor commands read this map when a formula handles a key. Reloading the page restores the catalog defaults.
 *
 * @file
 */

import { useQuery, useQueryClient } from '@tanstack/react-query'
import { editorCommandAction, editorCommands } from './editor-commands.ts'
import type { EditorCommand } from './editor-commands.ts'
import { defaultOverrides, shortcutKey } from './shortcut-overrides.ts'

/** Hold the shortcut labels recorded during this visit, and the palette rows that show them. */
export function useEditorCommandShortcuts() {
  const client = useQueryClient()
  const { data: overrides } = useQuery({ queryKey: shortcutKey, initialData: defaultOverrides, enabled: false })
  /** Apply a settings change directly to the cache used by keyboard handlers. */
  function setOverrides(update: (current: typeof defaultOverrides) => typeof defaultOverrides) {
    /** Use catalog defaults for a cache that has not been populated. */
    function apply(current: typeof defaultOverrides | undefined) {
      return update(current ?? defaultOverrides)
    }
    client.setQueryData(shortcutKey, apply)
  }

  /** Store one command's shortcut label. An empty string clears the label shown for that command. */
  function setShortcut(commandId: string, shortcut: string) {
    /** Keep every recorded label and replace the one for this command. */
    function writeOverride(current: Readonly<Record<string, string>>) {
      return { ...current, [commandId]: shortcut }
    }
    setOverrides(writeOverride)
  }

  /** Drop one command's recorded label so the catalog default shows again. */
  function resetShortcut(commandId: string) {
    /** Keep the other recorded labels and remove this command's entry. */
    function dropOverride(current: Readonly<Record<string, string>>) {
      if (!Object.hasOwn(current, commandId)) return current
      const next = { ...current }
      delete next[commandId]
      return next
    }
    setOverrides(dropOverride)
  }

  /** Pair each catalog command with the shortcut label currently recorded for it. */
  function toAction(command: EditorCommand) {
    return editorCommandAction(command, overrides)
  }

  return { overrides, actions: editorCommands.map(toAction), setShortcut, resetShortcut }
}
