/**
 * Switch the shared palette and color mode, and show those colors on notebook chrome. Contains the gallery controls for light and dark, the named palettes, and live samples of primary, secondary, and accent.
 *
 * @file
 */

import { useEffect, useState } from 'react'
import type { MouseEvent } from 'react'
import type { ColorMode, PaletteId, ThemeSelection } from './theme.ts'
import { applyTheme, defaultTheme, isColorMode, isPaletteId, paletteIds, paletteLabels, readStoredTheme } from './theme.ts'

/** Show the current primary, secondary, and accent, and switch palette or color mode. The choice is stored for the notebook too. */
export function ThemeControls() {
  const [theme, setTheme] = useState<ThemeSelection>(defaultTheme)

  useEffect(() => {
    setTheme(readStoredTheme())
  }, [])

  /** Store the palette named on the pressed choice. */
  function selectPalette(event: MouseEvent<HTMLButtonElement>) {
    const palette = event.currentTarget.dataset.palette ?? null
    if (!isPaletteId(palette)) return
    const next = { palette, colorMode: theme.colorMode }
    setTheme(next)
    applyTheme(next)
  }

  /** Store the color mode named on the pressed choice. */
  function selectColorMode(event: MouseEvent<HTMLButtonElement>) {
    const colorMode = event.currentTarget.dataset.colorMode ?? null
    if (!isColorMode(colorMode)) return
    const next = { palette: theme.palette, colorMode }
    setTheme(next)
    applyTheme(next)
  }

  /** Render one palette button with a dot for each role color. */
  function renderPaletteChoice(palette: PaletteId) {
    return <PaletteChoice key={palette} palette={palette} pressed={theme.palette === palette} onSelect={selectPalette} />
  }

  return (
    <section className="theme-panel" aria-labelledby="theme-heading">
      <h2 id="theme-heading">Theme</h2>
      <p className="primitive-row-copy">Primary, secondary, and accent live in client/src/theme/theme.css. Neutrals are shared. Pick a palette and a color mode here. The notebook uses the same tokens.</p>
      <div className="theme-controls">
        <div className="theme-choices" role="group" aria-label="Color mode">
          <ColorModeChoice colorMode="light" pressed={theme.colorMode === 'light'} onSelect={selectColorMode} />
          <ColorModeChoice colorMode="dark" pressed={theme.colorMode === 'dark'} onSelect={selectColorMode} />
        </div>
        <div className="theme-choices" role="group" aria-label="Palette">
          {paletteIds.map(renderPaletteChoice)}
        </div>
      </div>
      <ThemeUsage />
      <div className="type-specimens">
        <article className="type-specimen">
          <h3>UI</h3>
          <p className="type-ui">Menus, fields, and shortcuts use the system sans at 13px.</p>
        </article>
        <article className="type-specimen">
          <h3>Reading</h3>
          <p className="type-reading">
            Markdown notes use Georgia. A notebook needs the <a href="#theme-heading">why</a> as well as the working.
          </p>
        </article>
        <article className="type-specimen">
          <h3>Code</h3>
          <p className="type-code">## Make room for the reasoning</p>
        </article>
        <article className="type-specimen">
          <h3>Math</h3>
          <p className="type-math">
            ∫ <span className="theme-math-selection">f(x)</span> dx
          </p>
          <p className="type-caption">The highlight is the accent. Expressions themselves stay in MathLive.</p>
        </article>
      </div>
    </section>
  )
}

/** Press to apply one color mode. */
function ColorModeChoice({ colorMode, pressed, onSelect }: { colorMode: ColorMode; pressed: boolean; onSelect: (event: MouseEvent<HTMLButtonElement>) => void }) {
  const label = colorMode === 'light' ? 'Light' : 'Dark'
  return (
    <button type="button" className="theme-choice" data-color-mode={colorMode} aria-pressed={pressed} onClick={onSelect}>
      {label}
    </button>
  )
}

/** Press to apply one palette. The dots show that palette's light role colors. */
function PaletteChoice({ palette, pressed, onSelect }: { palette: PaletteId; pressed: boolean; onSelect: (event: MouseEvent<HTMLButtonElement>) => void }) {
  return (
    <button type="button" className="theme-choice" data-palette={palette} aria-pressed={pressed} onClick={onSelect}>
      <span className="theme-dots" aria-hidden="true">
        <span className="theme-dot theme-dot-primary" />
        <span className="theme-dot theme-dot-secondary" />
        <span className="theme-dot theme-dot-accent" />
      </span>
      {paletteLabels[palette]}
    </button>
  )
}

/** Show each role color on a control, so a palette change is visible without opening a menu. */
function ThemeUsage() {
  return (
    <div className="theme-usage">
      <article className="theme-role">
        <h3>Primary</h3>
        <span className="theme-button-primary">Insert math</span>
        <p className="type-caption">Filled actions, the focus ring, links, and the selected tab or page width.</p>
      </article>
      <article className="theme-role">
        <h3>Secondary</h3>
        <span className="theme-button-secondary">Edit</span>
        <p className="type-caption">Quiet buttons such as Edit and Done, and shortcut hints.</p>
      </article>
      <article className="theme-role">
        <h3>Accent</h3>
        <div className="theme-accent-row">
          <span>Add math cell</span>
          <span className="theme-kbd">Opt Cmd M</span>
        </div>
        <p className="type-caption">The highlighted menu row and the math selection.</p>
      </article>
    </div>
  )
}
