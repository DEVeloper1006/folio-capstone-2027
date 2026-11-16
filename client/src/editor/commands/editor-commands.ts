/**
 * List the notebook commands the palette and the shortcut table can show. Contains each command's stable id, label, search keywords, context label, and default shortcut label. Cursor movement commands are included from the cursor catalog. This file does not run a command.
 *
 * @file
 */

import { cursorCommandBindings } from './cursor-commands.ts'
import type { CursorCommandBinding } from './cursor-commands.ts'
import { formatShortcut } from './shortcut-label.ts'
import type { ShortcutKeyInput } from './shortcut-label.ts'
import type { ShortcutOverrides } from './shortcut-overrides.ts'
import { shortcutLabel } from './shortcut-overrides.ts'

/** Name one notebook command. `id` stays stable when the label changes. `when` is the context label shown in the shortcut table, and it is not evaluated. `shortcut` is only the label shown in the keybinding column. */
export interface EditorCommand {
  id: string
  label: string
  keywords: readonly string[]
  when: string
  shortcut?: string
}

/** Cell commands that act on the current notebook row. */
export const cellCommands = [
  { id: 'workspace.currentPage.cell.unfocus', label: 'Unfocus cell', keywords: ['blur', 'leave', 'finish'], when: 'cellFocus', shortcut: 'Esc' },
  { id: 'workspace.currentPage.cell.createBelow', label: 'Create cell below', keywords: ['add', 'insert', 'new'], when: 'cellFocus', shortcut: '⌘↩' },
  { id: 'workspace.currentPage.cell.duplicateBelow', label: 'Duplicate math cell below', keywords: ['copy', 'repeat'], when: 'mathFocus', shortcut: '⌘⇧↩' },
] as const satisfies readonly EditorCommand[]

/** Resolve a live binding. Both Control and Command activate the default primary-modifier shortcuts. A recorded binding matches exactly. */
export function workspaceCommandForKey(event: ShortcutKeyInput, overrides: ShortcutOverrides) {
  const key = formatShortcut(event)
  /** Match the recorded override or the platform equivalents of the catalog default. */
  function matches(command: EditorCommand) {
    const binding = shortcutLabel(command.id, command.shortcut, overrides)
    return binding === key || (!Object.hasOwn(overrides, command.id) && command.shortcut?.replace('⌘', '⌃') === key)
  }
  return workspaceCommands.find(matches)
}

/** Notebook commands that are not formula cursor movements, in the order the shortcut list shows them before the cursor commands. */
const workspaceCommands: readonly EditorCommand[] = [
  { id: 'workspace.command.open', label: 'Open the command menu', keywords: ['palette', 'search', 'commands'], when: 'workspace', shortcut: '⌘K' },
  { id: 'workspace.page.create', label: 'New page', keywords: ['add', 'page'], when: 'notebookFocus', shortcut: '⌘N' },
  { id: 'workspace.currentPage.cell.focusFirst', label: 'Focus first cell', keywords: ['top', 'start'], when: 'notebookFocus', shortcut: '⌘↑' },
  { id: 'workspace.currentPage.cell.focusLast', label: 'Focus last cell', keywords: ['bottom', 'end'], when: 'notebookFocus', shortcut: '⌘↓' },
  { id: 'workspace.currentPage.cell.focusAt', label: 'Focus cell by index', keywords: ['go to', 'number'], when: 'notebookFocus' },
  { id: 'workspace.sidebar.settings', label: 'Open settings menu', keywords: ['sidebar', 'preferences'], when: 'notebookFocus' },
  { id: 'workspace.page.actions', label: 'Open page actions', keywords: ['sidebar', 'menu'], when: 'notebookFocus' },
  { id: 'workspace.sidebar.hide', label: 'Hide sidebar', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.sidebar.show', label: 'Show sidebar', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.sidebar.collapse', label: 'Collapse sidebar', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.sidebar.expand', label: 'Expand sidebar', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.settings.theme', label: 'Open theme settings', keywords: ['appearance', 'palette', 'dark', 'light'], when: 'notebookFocus' },
  { id: 'workspace.settings.shortcuts', label: 'Open keyboard shortcuts', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.page.rename', label: 'Rename current page', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.page.delete', label: 'Delete current page', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.page.display', label: 'Open page display settings', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.page.full', label: 'Use full page width', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.page.narrow', label: 'Use narrow page width', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.page.scrollTop', label: 'Scroll to top of page', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.page.scrollBottom', label: 'Scroll to bottom of page', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.addMath', label: 'Append math cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.addMarkdown', label: 'Append Markdown cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.add', label: 'Append cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.copy', label: 'Copy cell', keywords: [], when: 'cellFocus' },
  { id: 'workspace.currentPage.cell.select', label: 'Select current cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.selectNext', label: 'Select next cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.selectPrevious', label: 'Select previous cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.selectFirst', label: 'Select first cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.selectLast', label: 'Select last cell', keywords: [], when: 'notebookFocus' },
  { id: 'workspace.currentPage.cell.view', label: 'View cell contents', keywords: ['focus', 'preview'], when: 'cellFocus' },
  { id: 'workspace.currentPage.cell.edit', label: 'Edit selected cell', keywords: [], when: 'cellFocus' },
  ...cellCommands,
  { id: 'workspace.currentPage.cell.createAbove', label: 'Create cell above', keywords: ['add', 'insert', 'new'], when: 'cellFocus' },
  { id: 'workspace.currentPage.cell.delete', label: 'Delete current cell', keywords: ['remove'], when: 'cellFocus', shortcut: '⌘⌫' },
]

/** Copy a cursor binding into the shared command row. The navigation action stays on the binding. */
function cursorEditorCommand(binding: CursorCommandBinding): EditorCommand {
  return { id: binding.id, label: binding.label, keywords: binding.keywords, when: binding.when, shortcut: binding.shortcut }
}

/** Notebook commands in the order the shortcut list shows before a search. */
export const editorCommands: readonly EditorCommand[] = [...workspaceCommands, ...cursorCommandBindings.map(cursorEditorCommand)]

/** Return the shortcut label to show. A recorded override replaces the catalog default, and an empty override clears it. */
export function editorCommandShortcut(command: EditorCommand, overrides: Readonly<Record<string, string>>) {
  return shortcutLabel(command.id, command.shortcut, overrides)
}

/** Report whether settings has recorded a shortcut label for this command. */
export function editorCommandShortcutIsCustom(command: EditorCommand, overrides: Readonly<Record<string, string>>) {
  return Object.hasOwn(overrides, command.id)
}

/** Build one palette row from a catalog command and the recorded shortcut labels. */
export function editorCommandAction(command: EditorCommand, overrides: Readonly<Record<string, string>>) {
  return { id: command.id, label: command.label, keywords: command.keywords, shortcut: editorCommandShortcut(command, overrides) }
}
