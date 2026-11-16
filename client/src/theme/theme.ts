/**
 * Read and apply the selected palette and color mode. Contains the palette ids, the stored theme, and the document attributes that theme.css listens for.
 *
 * @file
 */

/** Palettes defined in theme.css. Ink is the default. Paper, Chalk, Harbor, and Margin sit beside Forest and Dusk. */
export const paletteIds = ['ink', 'forest', 'dusk', 'paper', 'chalk', 'harbor', 'margin'] as const

/** A named set of primary, secondary, and accent colors. */
export type PaletteId = (typeof paletteIds)[number]

/** Light or dark neutrals. Role colors have a matching value for each mode. */
export type ColorMode = 'light' | 'dark'

/** The palette and color mode currently applied to the document. */
export interface ThemeSelection {
  palette: PaletteId
  colorMode: ColorMode
}

/** Ink on a light canvas, used before a stored choice is available. */
export const defaultTheme: ThemeSelection = {
  palette: 'ink',
  colorMode: 'light',
}

/** Labels for the palette switcher. */
export const paletteLabels: Record<PaletteId, string> = {
  ink: 'Ink',
  forest: 'Forest',
  dusk: 'Dusk',
  paper: 'Paper',
  chalk: 'Chalk',
  harbor: 'Harbor',
  margin: 'Margin',
}

const paletteStorageKey = 'folio-palette'
const colorModeStorageKey = 'folio-color-mode'

/** Accept only palette ids that theme.css defines. */
export function isPaletteId(value: string | null): value is PaletteId {
  if (value === null) return false

  /** Compare one known palette id with the candidate. */
  function paletteMatches(palette: PaletteId) {
    return palette === value
  }

  return paletteIds.some(paletteMatches)
}

/** Accept only the two color modes. */
export function isColorMode(value: string | null): value is ColorMode {
  return value === 'light' || value === 'dark'
}

/** Read the theme already on the document, or the default when the attributes are absent. */
export function readStoredTheme(): ThemeSelection {
  if (typeof document === 'undefined') return defaultTheme
  const palette = document.documentElement.dataset.palette ?? null
  const colorMode = document.documentElement.dataset.colorMode ?? null
  return {
    palette: isPaletteId(palette) ? palette : defaultTheme.palette,
    colorMode: isColorMode(colorMode) ? colorMode : defaultTheme.colorMode,
  }
}

/** Set the document attributes theme.css uses, and remember the choice for the next visit. */
export function applyTheme(selection: ThemeSelection) {
  const root = document.documentElement
  root.dataset.palette = selection.palette
  root.dataset.colorMode = selection.colorMode
  try {
    localStorage.setItem(paletteStorageKey, selection.palette)
    localStorage.setItem(colorModeStorageKey, selection.colorMode)
  } catch {
    // Private browsing can reject storage. The document attributes still update this view.
  }
}
