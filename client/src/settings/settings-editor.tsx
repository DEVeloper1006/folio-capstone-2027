/**
 * Present searchable preference controls and the existing shortcut recorder. Save each complete edit through the validated settings writer, retaining saved custom subjects and reporting conflicts without overwriting them.
 *
 * @file
 */
import { useEffect, useRef, useState } from 'react'
import type { ChangeEvent, KeyboardEvent } from 'react'
import { Button } from '../component-library'
import { CommandSettingsView } from '../components/command-settings-view'
import { isPaletteId, paletteIds, paletteLabels } from '../theme/theme'
import { builtinModes } from '../math-help/math-modes'
import type { MathMode } from '../math-help/math-modes'
import { settingsOverrides } from './settings'
import type { FolioSettings } from './settings'
import type { SettingsDocument } from './use-settings'
import { SettingsSubjects } from './settings-subjects'
import './settings.css'

export type SettingsCategory = 'appearance' | 'editor' | 'math' | 'shortcuts'
const categories: { id: SettingsCategory; label: string }[] = [
  { id: 'appearance', label: 'Appearance' },
  { id: 'editor', label: 'Editor' },
  { id: 'math', label: 'Math help' },
  { id: 'shortcuts', label: 'Keyboard shortcuts' },
]

/** Keep incomplete typing local; commit a complete text or number when focus leaves the field or Enter is pressed. */
function SettingsInput({ label, value, type = 'text', onCommit }: { label: string; value: string | number; type?: 'text' | 'number'; onCommit: (value: string) => void }) {
  const [text, setText] = useState(String(value))
  /** Reflect saved or externally updated preferences. */
  function sync() {
    setText(String(value))
  }
  useEffect(sync, [value])
  /** Retain typing without writing partial values to disk. */
  function edit(event: ChangeEvent<HTMLInputElement>) {
    setText(event.target.value)
  }
  /** Save only actual changes to the preference. */
  function commit() {
    if (text !== String(value)) onCommit(text)
  }
  /** Use Enter to finish editing without submitting another control. */
  function key(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Enter') {
      event.preventDefault()
      event.currentTarget.blur()
    }
  }
  return <input aria-label={label} type={type} min={type === 'number' ? 10 : undefined} max={type === 'number' ? 48 : undefined} value={text} onChange={edit} onBlur={commit} onKeyDown={key} spellCheck={false} />
}

/** Edit ordinary preferences with native controls and persist recorded shortcuts through the same validation path. */
export function SettingsEditor({
  document,
  settings,
  save,
  reload,
  active,
  category,
  onCategoryChange,
  paletteOpen,
  onOpenCommandPalette,
}: {
  document: SettingsDocument
  settings: FolioSettings
  save: (text: string, expected: string) => Promise<void>
  reload: () => Promise<void>
  active: boolean
  category: SettingsCategory
  onCategoryChange: (category: SettingsCategory) => void
  paletteOpen: boolean
  onOpenCommandPalette: () => void
}) {
  const [query, setQuery] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)
  const saving = useRef(false)
  const normalized = query.trim().toLowerCase()
  /** Clear a previous search when a menu or command opens a specific category. */
  function categoryChanged() {
    setQuery('')
  }
  useEffect(categoryChanged, [category])
  /** Serialize a complete settings value and leave applied preferences intact if validation or persistence fails. */
  async function update(next: FolioSettings) {
    if (saving.current) return false
    saving.current = true
    setBusy(true)
    setError('')
    setSaved(false)
    try {
      await save(JSON.stringify(next, null, 2) + '\n', document.text)
      setSaved(true)
      return true
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause))
      return false
    } finally {
      saving.current = false
      setBusy(false)
    }
  }
  /** Refresh preferences after a conflicting external save. */
  async function refresh() {
    setError('')
    setSaved(false)
    await reload()
  }
  /** Repair an invalid external file using the preferences still applied in this session. */
  function restoreApplied() {
    void update(settings)
  }
  /** Search preference names and descriptions across categories. */
  function search(event: ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
  }
  /** Show matching groups while searching, otherwise show the selected category. */
  function visible(id: SettingsCategory, terms: string) {
    /** Match every search word regardless of its order in the setting descriptions. */
    function includes(word: string) {
      return terms.toLowerCase().includes(word)
    }
    return normalized ? normalized.split(/\s+/).every(includes) : category === id
  }
  /** Render a category button with its current selection exposed to assistive technology. */
  function navigation(item: (typeof categories)[number]) {
    /** Switch categories without changing any preferences. */
    function choose() {
      setQuery('')
      onCategoryChange(item.id)
    }
    return (
      <button key={item.id} type="button" aria-current={!normalized && category === item.id ? 'page' : undefined} onClick={choose}>
        {item.label}
      </button>
    )
  }
  /** Apply one of the available color palettes. */
  function palette(event: ChangeEvent<HTMLSelectElement>) {
    if (isPaletteId(event.target.value)) void update({ ...settings, theme: { ...settings.theme, palette: event.target.value } })
  }
  /** Apply light, dark, or operating-system appearance. */
  function appearance(event: ChangeEvent<HTMLSelectElement>) {
    const mode = event.target.value
    if (mode === 'light' || mode === 'dark' || mode === 'system') void update({ ...settings, theme: { ...settings.theme, mode } })
  }
  /** Toggle optional inline math completion. */
  function autocomplete(event: ChangeEvent<HTMLInputElement>) {
    void update({ ...settings, editor: { ...settings.editor, autocomplete: event.target.checked } })
  }
  /** Validate and apply the reading size in pixels. */
  function textSize(value: string) {
    void update({ ...settings, editor: { ...settings.editor, text_size: Number(value) } })
  }
  /** Validate and apply the formula size in pixels. */
  function mathSize(value: string) {
    void update({ ...settings, editor: { ...settings.editor, math_size: Number(value) } })
  }
  /** Set the installed local model used by hints and subject detection. */
  function model(value: string) {
    void update({ ...settings, math: { ...settings.math, model: value.trim() } })
  }
  /** Enable automatic subject selection while respecting per-problem manual choices. */
  function detect(event: ChangeEvent<HTMLInputElement>) {
    void update({ ...settings, math: { ...settings.math, suggest_modes: event.target.checked } })
  }
  /** Set the subject used before detection or a manual choice. */
  function subject(event: ChangeEvent<HTMLSelectElement>) {
    void update({ ...settings, math: { ...settings.math, default_mode: event.target.value } })
  }
  /** Present built-in and custom subjects by their readable names. */
  function subjectOption(mode: MathMode) {
    return (
      <option key={mode.id} value={mode.id}>
        {mode.title}
      </option>
    )
  }
  /** Present the existing named palettes. */
  function paletteOption(id: (typeof paletteIds)[number]) {
    return (
      <option key={id} value={id}>
        {paletteLabels[id]}
      </option>
    )
  }
  /** Persist the recorder's canonical binding, including an empty string to disable a command. */
  function shortcut(id: string, _label: string, binding: string) {
    void update({ ...settings, keybindings: { ...settings.keybindings, [id]: binding } })
  }
  /** Remove the override so the catalog's default shortcut applies again. */
  function resetShortcut(id: string) {
    const keybindings = { ...settings.keybindings }
    delete keybindings[id]
    void update({ ...settings, keybindings })
  }
  /** Save the complete validated custom subject library without altering other preferences. */
  function subjects(modes: MathMode[]) {
    return update({ ...settings, math: { ...settings.math, modes } })
  }
  const showAppearance = visible('appearance', 'appearance theme palette colors light dark system')
  const showEditor = visible('editor', 'editor font text math size autocomplete completion')
  const showMath = visible('math', 'math help ai local model ollama subject detection custom notation')
  const showShortcuts = visible('shortcuts', 'keyboard shortcuts keybindings commands')
  return (
    <section className="settings-editor" aria-label="Folio settings">
      <header className="settings-heading">
        <h1>Settings</h1>
        <p>Changes save automatically. Text fields save when you leave them or press Enter.</p>
      </header>
      <input className="settings-search" type="search" aria-label="Search settings" placeholder="Search settings" value={query} onChange={search} />
      <div className="settings-layout">
        <nav className="settings-navigation" aria-label="Settings categories">
          {categories.map(navigation)}
        </nav>
        <div className="settings-content">
          <div className="settings-status" role="status">
            {error || document.error || (busy ? 'Saving…' : saved ? 'Saved' : '')}
          </div>
          {(error || document.error) && (
            <div className="settings-actions">
              <Button variant="quiet" onClick={refresh} disabled={busy}>
                Reload settings
              </Button>
              {document.error && (
                <Button onClick={restoreApplied} disabled={busy}>
                  Use last applied settings
                </Button>
              )}
            </div>
          )}
          <fieldset disabled={busy || !document.path || !!document.error}>
            {showAppearance && (
              <section className="settings-group" aria-label="Appearance settings">
                <h2>Appearance</h2>
                <label className="settings-row">
                  <span>
                    <strong>Color theme</strong>
                    <small>Choose Folio’s accent colors.</small>
                  </span>
                  <select aria-label="Color theme" value={settings.theme.palette} onChange={palette}>
                    {paletteIds.map(paletteOption)}
                  </select>
                </label>
                <label className="settings-row">
                  <span>
                    <strong>Appearance</strong>
                    <small>Follow your system, or choose a light or dark workspace.</small>
                  </span>
                  <select aria-label="Appearance" value={settings.theme.mode} onChange={appearance}>
                    <option value="system">System</option>
                    <option value="light">Light</option>
                    <option value="dark">Dark</option>
                  </select>
                </label>
              </section>
            )}
            {showEditor && (
              <section className="settings-group" aria-label="Editor settings">
                <h2>Editor</h2>
                <label className="settings-row">
                  <span>
                    <strong>Text size</strong>
                    <small>Reading size in pixels, from 10 to 48.</small>
                  </span>
                  <SettingsInput label="Text size" type="number" value={settings.editor.text_size} onCommit={textSize} />
                </label>
                <label className="settings-row">
                  <span>
                    <strong>Math size</strong>
                    <small>Formula size in pixels, from 10 to 48.</small>
                  </span>
                  <SettingsInput label="Math size" type="number" value={settings.editor.math_size} onCommit={mathSize} />
                </label>
                <label className="settings-row">
                  <span>
                    <strong>Math autocomplete</strong>
                    <small>Suggest notation while you write formulas.</small>
                  </span>
                  <input aria-label="Math autocomplete" type="checkbox" checked={settings.editor.autocomplete} onChange={autocomplete} />
                </label>
              </section>
            )}
            {showMath && (
              <section className="settings-group" aria-label="Math help settings">
                <h2>Math help</h2>
                <label className="settings-row">
                  <span>
                    <strong>Local model</strong>
                    <small>The name of a model already installed in Ollama.</small>
                  </span>
                  <SettingsInput label="Local model" value={settings.math.model} onCommit={model} />
                </label>
                <label className="settings-row">
                  <span>
                    <strong>Detect subjects automatically</strong>
                    <small>Recognize the subject of your current problem.</small>
                  </span>
                  <input aria-label="Detect subjects automatically" type="checkbox" checked={settings.math.suggest_modes} onChange={detect} />
                </label>
                <label className="settings-row">
                  <span>
                    <strong>Default subject</strong>
                    <small>Used before automatic detection or a manual selection.</small>
                  </span>
                  <select aria-label="Default subject" value={settings.math.default_mode} onChange={subject}>
                    {[...builtinModes, ...settings.math.modes].map(subjectOption)}
                  </select>
                </label>
                <SettingsSubjects modes={settings.math.modes} onSave={subjects} />
              </section>
            )}
            {active && showShortcuts && <CommandSettingsView overrides={settingsOverrides(settings)} paletteOpen={paletteOpen} onShortcutChange={shortcut} onResetShortcut={resetShortcut} onOpenCommandPalette={onOpenCommandPalette} />}
            {!showAppearance && !showEditor && !showMath && !showShortcuts && <p className="settings-empty">No settings match “{query}”.</p>}
          </fieldset>
        </div>
      </div>
    </section>
  )
}
