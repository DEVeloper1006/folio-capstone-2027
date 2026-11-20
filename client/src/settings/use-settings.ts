/**
 * Load one settings document, publish validated preferences to existing theme and command consumers, and retain the last applied values when an external edit is invalid. Desktop uses the real file; browser previews use local storage.
 *
 * @file
 */
import { useEffect, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { defaultSettings, parseSettings, settingsOverrides } from './settings'
import { applyTheme, readStoredTheme } from '../theme/theme'
import { shortcutKey } from '../editor/commands/shortcut-overrides'

export const appliedSettingsKey = ['settings', 'applied'] as const
const browserKey = 'folio:settings'
export interface SettingsDocument {
  path: string
  text: string
  error: string | null
}

/** Own the file subscription once at the workspace root and keep editor drafts separate from disk state. */
export function useSettings() {
  const client = useQueryClient()
  const { data: settings } = useQuery({ queryKey: appliedSettingsKey, initialData: defaultSettings, enabled: false })
  const [document, setDocument] = useState<SettingsDocument>({ path: '', text: '', error: null })
  const sequence = useRef(0)

  /** Publish all preferences together only after parsing succeeds. */
  function publish(record: { path: string; text: string }) {
    try {
      const next = parseSettings(record.text)
      client.setQueryData(appliedSettingsKey, next)
      client.setQueryData(shortcutKey, settingsOverrides(next))
      setDocument({ ...record, error: null })
    } catch (error) {
      setDocument({ ...record, error: error instanceof Error ? error.message : String(error) })
    }
  }
  /** Read the file without overwriting it; create initial settings from the existing theme only on first use. */
  async function reload() {
    const request = ++sequence.current
    const theme = readStoredTheme()
    const initial = JSON.stringify({ ...defaultSettings, theme: { palette: theme.palette, mode: theme.colorMode } }, null, 2) + '\n'
    try {
      let record
      if (window.folioDesktop) record = await window.folioDesktop.readSettings(initial)
      else {
        let text = localStorage.getItem(browserKey)
        if (text === null) {
          localStorage.setItem(browserKey, initial)
          text = initial
        }
        record = { path: 'Browser storage · settings.json', text }
      }
      if (request === sequence.current) publish(record)
    } catch (error) {
      if (request === sequence.current) setDocument({ ...document, error: error instanceof Error ? error.message : String(error) })
    }
  }
  /** Validate first, reject conflicting disk edits, persist, then apply. */
  async function save(text: string, expected: string) {
    parseSettings(text)
    const request = ++sequence.current
    let record
    if (window.folioDesktop) record = await window.folioDesktop.saveSettings(text, expected)
    else {
      if (localStorage.getItem(browserKey) !== expected) throw new Error('Settings changed elsewhere. Reload before saving.')
      localStorage.setItem(browserKey, text)
      record = { path: 'Browser storage · settings.json', text }
    }
    if (request === sequence.current) publish(record)
  }
  /** Load once, then reload external saves; the editor preserves unsaved drafts separately. */
  function subscribe() {
    void reload()
    /** Read externally changed preferences through the same validation path. */
    function changed() {
      void reload()
    }
    const unsubscribe = window.folioDesktop?.onSettingsChanged(changed)
    window.addEventListener('storage', changed)
    /** Release listeners and invalidate reads from an unmounted workspace. */
    function stop() {
      sequence.current++
      unsubscribe?.()
      window.removeEventListener('storage', changed)
    }
    return stop
  }
  useEffect(subscribe, [])
  /** Apply theme and font tokens live, including operating-system appearance changes. */
  function appearance() {
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    /** Resolve system mode without changing the user's stored preference. */
    function paint() {
      const colorMode = settings.theme.mode === 'system' ? (media.matches ? 'dark' : 'light') : settings.theme.mode
      applyTheme({ palette: settings.theme.palette, colorMode })
      window.document.documentElement.style.setProperty('--text-reading-size', `${settings.editor.text_size}px`)
      window.document.documentElement.style.setProperty('--text-math-size', `${settings.editor.math_size}px`)
    }
    paint()
    media.addEventListener('change', paint)
    /** Release the operating-system theme listener when settings change. */
    function stop() {
      media.removeEventListener('change', paint)
    }
    return stop
  }
  useEffect(appearance, [settings])
  return { document, settings, reload, save }
}
