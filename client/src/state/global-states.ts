/**
 * Name the application records that outlive one component. Contains the notebook pages, the settings record, and the map that keeps those records separate.
 *
 * @file
 */

import type { Page } from '#/notebook/page.ts'
import { readStoredTheme } from '#/theme/theme.ts'
import type { ThemeSelection } from '#/theme/theme.ts'

/** Sidebar identity and title, stored separately from editable cell content. */
export type PageSummary = Pick<Page, 'pageId' | 'title'>

/** The ordered sidebar records and id of the selected page. */
export interface NotebookState {
  pages: readonly PageSummary[]
  openPageId: string
}

/** Preferences that apply across pages. The theme field is the palette and color mode. Page width and cell spacing stay on each page. */
export interface SettingsState {
  theme: ThemeSelection
}

/**
 * The global states the app stores separately. `notebook` is represented by the React Query page list and page records. `settings` is the theme selection the theme module restores before paint. An editor record, a chat record, and a background record join this map as their own fields when those
 * domains exist. They do not become fields of the notebook. A focused cell, a slash-menu session, and Markdown edit mode stay on the component that renders them.
 */
export interface GlobalStates {
  notebook: NotebookState
  settings: SettingsState
}

/** Read the settings record from the theme already applied to the document. */
export function readSettingsState(): SettingsState {
  return { theme: readStoredTheme() }
}
