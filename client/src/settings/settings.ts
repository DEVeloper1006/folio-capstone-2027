/**
 * Validate the editable Folio settings document and translate readable keybindings into the existing command labels. Omitted keys inherit defaults; unknown keys and invalid values are rejected before anything is applied.
 *
 * @file
 */
import { defaultMathPreferences, parseMathPreferences } from '../math-help/math-modes'
import type { MathPreferences } from '../math-help/math-modes'
import { editorCommands } from '../editor/commands/editor-commands'
import { formatShortcut } from '../editor/commands/shortcut-label'
import { defaultTheme, isPaletteId } from '../theme/theme'
import type { PaletteId } from '../theme/theme'

export interface FolioSettings {
  theme: { palette: PaletteId; mode: 'light' | 'dark' | 'system' }
  editor: { autocomplete: boolean; text_size: number; math_size: number }
  keybindings: Record<string, string>
  math: MathPreferences
}
export const defaultSettings: FolioSettings = { theme: { palette: defaultTheme.palette, mode: defaultTheme.colorMode }, editor: { autocomplete: true, text_size: 15, math_size: 21 }, keybindings: {}, math: defaultMathPreferences }

/** Require a JSON object with only documented properties. */
function object(value: unknown, name: string, keys?: string[]): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${name} must be an object.`)
  if (keys) for (const key of Object.keys(value)) if (!keys.includes(key)) throw new Error(`Unknown setting: ${name}.${key}`)
  return Object.fromEntries(Object.entries(value))
}

/** Require a supported font size in CSS pixels. */
function size(value: unknown, name: string, initial: number) {
  if (value === undefined) return initial
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 10 || value > 48) throw new Error(`${name} must be a number from 10 to 48.`)
  return value
}

/** Convert one explicit shortcut, such as cmd+shift+k, to the label already used by key dispatch. Empty strings disable a binding. */
export function bindingLabel(binding: string): string {
  if (binding === '') return ''
  const parts = binding.toLowerCase().split('+')
  const key = parts.pop()
  const modifiers = new Set(parts)
  if (!key || modifiers.size !== parts.length || parts.some(unknownModifier)) throw new Error(`Invalid keybinding "${binding}". Use cmd, ctrl, alt, shift plus one key.`)
  const names: Record<string, string> = {
    up: 'ArrowUp',
    down: 'ArrowDown',
    left: 'ArrowLeft',
    right: 'ArrowRight',
    enter: 'Enter',
    escape: 'Escape',
    backspace: 'Backspace',
    delete: 'Delete',
    tab: 'Tab',
    space: ' ',
    plus: '+',
    minus: '-',
    home: 'Home',
    end: 'End',
    pageup: 'PageUp',
    pagedown: 'PageDown',
  }
  const named = Object.hasOwn(names, key) ? names[key] : undefined
  const resolved = named ?? (/^f([1-9]|1[0-9]|2[0-4])$/.test(key) ? key.toUpperCase() : key)
  if (!named && key.length !== 1 && !/^f([1-9]|1[0-9]|2[0-4])$/.test(key)) throw new Error(`Unknown key "${key}" in "${binding}".`)
  return formatShortcut({ key: resolved, metaKey: modifiers.has('cmd'), ctrlKey: modifiers.has('ctrl'), altKey: modifiers.has('alt'), shiftKey: modifiers.has('shift') })
}
/** Reject unsupported modifier names rather than accepting a binding that never fires. */
function unknownModifier(value: string) {
  return !['cmd', 'ctrl', 'alt', 'shift'].includes(value)
}

/** Parse the entire document before changing theme, keyboard behavior, or persistence. */
export function parseSettings(text: string): FolioSettings {
  const value: unknown = JSON.parse(text)
  const root = object(value, 'settings', ['theme', 'editor', 'keybindings', 'math'])
  const theme = object(root.theme === undefined ? {} : root.theme, 'theme', ['palette', 'mode'])
  const palette = theme.palette === undefined ? defaultSettings.theme.palette : theme.palette
  const mode = theme.mode === undefined ? defaultSettings.theme.mode : theme.mode
  if (typeof palette !== 'string' || !isPaletteId(palette)) throw new Error('theme.palette must be ink, forest, dusk, paper, chalk, harbor, or margin.')
  if (mode !== 'light' && mode !== 'dark' && mode !== 'system') throw new Error('theme.mode must be light, dark, or system.')
  const editor = object(root.editor === undefined ? {} : root.editor, 'editor', ['autocomplete', 'text_size', 'math_size'])
  const autocomplete = editor.autocomplete === undefined ? defaultSettings.editor.autocomplete : editor.autocomplete
  if (typeof autocomplete !== 'boolean') throw new Error('editor.autocomplete must be true or false.')
  const keybindings: Record<string, string> = {}
  const entries = object(root.keybindings === undefined ? {} : root.keybindings, 'keybindings')
  for (const [id, binding] of Object.entries(entries)) {
    /** Match a command from the real runtime catalog. */
    function matches(command: (typeof editorCommands)[number]) {
      return command.id === id
    }
    if (!editorCommands.some(matches)) throw new Error(`Unknown command: ${id}`)
    if (typeof binding !== 'string') throw new Error(`keybindings.${id} must be a string; use "" to disable it.`)
    bindingLabel(binding)
    keybindings[id] = binding
  }
  // Reject explicit collisions rather than saving a shortcut that another command intercepts.
  for (const command of editorCommands) {
    if (!Object.hasOwn(keybindings, command.id)) continue
    const label = bindingLabel(keybindings[command.id])
    if (!label) continue
    for (const other of editorCommands) {
      if (other.id === command.id) continue
      const otherLabel = Object.hasOwn(keybindings, other.id) ? bindingLabel(keybindings[other.id]) : other.shortcut
      if (label === otherLabel || (!Object.hasOwn(keybindings, other.id) && label === otherLabel?.replace('⌘', '⌃'))) throw new Error(`Shortcut ${label} is already assigned to “${other.label}”. Change or remove that binding first.`)
    }
  }
  return { theme: { palette, mode }, editor: { autocomplete, text_size: size(editor.text_size, 'editor.text_size', defaultSettings.editor.text_size), math_size: size(editor.math_size, 'editor.math_size', 21) }, keybindings, math: parseMathPreferences(root.math) }
}

/** Translate only explicit overrides, leaving the catalog's default behavior intact. */
export function settingsOverrides(settings: FolioSettings) {
  const overrides: Record<string, string> = {}
  for (const [id, binding] of Object.entries(settings.keybindings)) overrides[id] = bindingLabel(binding)
  return overrides
}
