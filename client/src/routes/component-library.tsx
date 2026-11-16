/**
 * Show the shared notebook controls at /component-library. Contains one controlled example of each control and the page-menu composition.
 *
 * @file
 */

import { createFileRoute } from '@tanstack/react-router'
import { useState } from 'react'
import type { ChangeEvent } from 'react'
import { Button, Popover, SegmentedControl, TextField } from '#/component-library/index.ts'
import type { SegmentedOption } from '#/component-library/index.ts'

/** Name the gallery in the document title. */
function componentLibraryHead() {
  return {
    meta: [{ title: 'Components · Folio' }],
  }
}

export const Route = createFileRoute('/component-library')({
  head: componentLibraryHead,
  component: ComponentLibraryPage,
})

type PreviewWidth = 'regular' | 'full'

const previewWidthOptions: ReadonlyArray<SegmentedOption<PreviewWidth>> = [
  { value: 'regular', label: 'Regular' },
  { value: 'full', label: 'Full' },
]

/** Render the shared controls with local display state so the gallery can be tried without changing a notebook. */
function ComponentLibraryPage() {
  const [cellSpacingPx, setCellSpacingPx] = useState(16)
  const [width, setWidth] = useState<PreviewWidth>('regular')

  /** Keep a non-negative pixel distance in the spacing example. */
  function handleSpacingChange(event: ChangeEvent<HTMLInputElement>) {
    const nextSpacingPx = event.target.valueAsNumber
    if (!Number.isFinite(nextSpacingPx) || nextSpacingPx < 0) return
    setCellSpacingPx(nextSpacingPx)
  }

  /** Store the pressed page-width example. */
  function handleWidthChange(nextWidth: PreviewWidth) {
    setWidth(nextWidth)
  }

  return (
    <main className="component-library">
      <header>
        <h1>Components</h1>
        <p>Shared notebook controls. The same button, field, choice, and popover are used by the page menu, add-cell actions, and Markdown editing.</p>
      </header>
      <section className="component-library-section" aria-labelledby="button-heading">
        <h2 id="button-heading">Button</h2>
        <div className="component-library-row">
          <Button>Edit</Button>
          <Button variant="quiet">+ Math</Button>
          <Button variant="icon" aria-label="Page display">
            ···
          </Button>
        </div>
      </section>
      <section className="component-library-section" aria-labelledby="field-heading">
        <h2 id="field-heading">Text field</h2>
        <TextField label="Cell spacing" type="number" min={0} step={4} suffix="px" value={cellSpacingPx} onChange={handleSpacingChange} />
      </section>
      <section className="component-library-section" aria-labelledby="segmented-heading">
        <h2 id="segmented-heading">Segmented control</h2>
        <SegmentedControl label="Page width" value={width} options={previewWidthOptions} onValueChange={handleWidthChange} />
      </section>
      <section className="component-library-section" aria-labelledby="popover-heading">
        <h2 id="popover-heading">Popover</h2>
        <Popover label="Page display" trigger="···">
          <TextField label="Cell spacing" type="number" min={0} step={4} suffix="px" value={cellSpacingPx} onChange={handleSpacingChange} />
          <SegmentedControl label="Page width" value={width} options={previewWidthOptions} onValueChange={handleWidthChange} />
        </Popover>
      </section>
    </main>
  )
}
