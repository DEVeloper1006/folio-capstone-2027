/**
 * Show the component gallery at /component-library, grouped into theme, notebook, command palette, sidebars, chat, agent, and control sections. The chat section includes a working sidebar dock and a full-screen assistant. Both answer with the same mock reply.
 *
 * @file
 */

import { Tooltip } from '@base-ui/react/tooltip'
import { createFileRoute } from '@tanstack/react-router'
import type { ReactNode } from 'react'
import { AgentToolCards } from '#/component-library/primitives/agent-tool-specimens.tsx'
import { BaseCheckbox, BaseContextMenu, BaseDialog, BaseDisclosure, BaseExpressionSearch, BaseHoverCard, BaseMenu, BasePageWidth, BasePopover, BaseShortcutList, BaseSpacing, BaseTabs, BaseToolbar, BaseTooltip } from '#/component-library/primitives/base-ui-primitives.tsx'
import { ChatContextAttachments, SelectionToChat } from '#/component-library/primitives/chat-context-specimens.tsx'
import { FullScreenChat, SidebarChat } from '#/component-library/primitives/chat-surfaces.tsx'
import { CellStates, MatrixBuilderSpecimen, CommandPaletteSpecimen, IconSet, InlineSuggestion, SpeechInput } from '#/component-library/primitives/notebook-specimens.tsx'
import { PageSidebarSpecimen } from '#/component-library/primitives/sidebar-specimens.tsx'
import { ThemeControls } from '#/theme/theme-controls.tsx'
import showcaseStylesheetUrl from '../component-library/primitives/primitive-showcase.css?url'

/** Name the gallery and load its layout styles. Theme tokens load with the document. */
function componentLibraryHead() {
  return {
    meta: [{ title: 'Components · Folio' }],
    links: [{ rel: 'stylesheet', href: showcaseStylesheetUrl }],
  }
}

export const Route = createFileRoute('/component-library')({
  head: componentLibraryHead,
  component: ComponentLibraryPage,
})

/** Describe one specimen card inside a gallery section. */
interface PrimitiveSpecimen {
  id: string
  title: string
  detail: string
  sample: ReactNode
}

/** Describe one gallery section and the specimens it contains. */
interface GallerySection {
  id: string
  title: string
  detail: string
  specimens: readonly PrimitiveSpecimen[]
}

/** A jump target in the gallery nav. Theme is rendered separately because its controls own their heading. */
interface GalleryNavItem {
  id: string
  title: string
}

const notebookSpecimens: readonly PrimitiveSpecimen[] = [
  {
    id: 'icons',
    title: 'Icons & tooltips',
    detail: 'Named Lucide imports (~60 B gzipped per glyph) paired with Base UI tooltips. Hover or focus any icon to see its description and shortcut.',
    sample: <IconSet />,
  },
  {
    id: 'toolbar',
    title: 'Formatting toolbar',
    detail: 'Compact icon toggles for bold, italic, code, inline math, headings, lists, quotes, and links. Arrow keys move across the bar and tooltips show shortcuts.',
    sample: <BaseToolbar />,
  },
  {
    id: 'cell-states',
    title: 'Cell states',
    detail: 'Seven real editable MathLive LatexCells showing unselected, empty, focused, editing, selected, computing, and error states. Click into any formula to navigate or edit it.',
    sample: <CellStates />,
  },
  { id: 'matrix-builder', title: 'Matrix builder', detail: 'Dimensions, delimiters and sparse coordinates using the same controls as the expression menu.', sample: <MatrixBuilderSpecimen /> },
  {
    id: 'suggestion',
    title: 'Inline suggestion',
    detail: 'Ghost LaTeX and Markdown continuations inside a cell, with an inline icon trigger to accept. Tab accepts and Escape dismisses.',
    sample: <InlineSuggestion />,
  },
  {
    id: 'speech',
    title: 'Speech to text',
    detail: 'Compact microphone toggle with a shortcut tooltip. When pressed, spoken math and prose stream into the focused cell.',
    sample: <SpeechInput />,
  },
]

const commandPaletteSpecimens: readonly PrimitiveSpecimen[] = [
  {
    id: 'command-palette-shell',
    title: 'Search and run',
    detail: 'The pointer and the arrow keys share one highlighted row. Moving the pointer selects the row under it, and the arrow keys then move that highlight until the pointer moves again. Enter runs it. These sample actions only record their name. Shortcuts are labels and are not bound yet.',
    sample: <CommandPaletteSpecimen />,
  },
]

const sidebarSpecimens: readonly PrimitiveSpecimen[] = [
  {
    id: 'page-sidebar',
    title: 'Page list',
    detail: 'The new-page control is an icon with a tooltip. Each page is left aligned, with a page icon, a three-dot menu, and the same actions on right-click. The settings menu at the bottom opens the shortcut list or the command palette. This sample page is view-only.',
    sample: <PageSidebarSpecimen />,
  },
]

const chatSpecimens: readonly PrimitiveSpecimen[] = [
  {
    id: 'sidebar-chat',
    title: 'Sidebar chat',
    detail: 'An assistant docked beside a notebook page. Type a message or choose a suggestion. $ inserts a MathLive expression, Enter sends, and Escape stops the reply. Closing the dock keeps the thread.',
    sample: <SidebarChat />,
  },
  {
    id: 'fullscreen-chat',
    title: 'Full screen chat',
    detail: 'The same assistant filling the page. $ inserts a MathLive expression instead of raw LaTeX. Every message, including the suggestions, receives the same mock reply.',
    sample: <FullScreenChat />,
  },
  {
    id: 'selection-to-chat',
    title: 'Selecting sub-expressions & cells for chat',
    detail: 'Drag across a formula to highlight it. The paint follows each glyph region, so a selection can be separate boxes, a stepped fraction, or a tall operator beside a shorter symbol. Add that highlight to the chat tray.',
    sample: <SelectionToChat />,
  },
  {
    id: 'chat-context',
    title: 'Chat context attachments & hover previews',
    detail: 'Attach cells, sub-expressions, long pasted logs, arXiv/web links, or PDFs via @. Hover any pill to preview its typeset formula, parent expression, or excerpt.',
    sample: <ChatContextAttachments />,
  },
]

const agentSpecimens: readonly PrimitiveSpecimen[] = [
  {
    id: 'tool-calls',
    title: 'Agent tool call cards',
    detail: 'Result and review cards for symbolic CAS evaluation, algebraic step verification, proposed cell LaTeX diffs, Python sandbox runs, notebook search, and PDF/theorem lookup.',
    sample: <AgentToolCards />,
  },
]

const controlSpecimens: readonly PrimitiveSpecimen[] = [
  {
    id: 'menu',
    title: 'Menu',
    detail: 'Overflow icon trigger with a tooltip. Menu items pair icons with right-aligned shortcut badges.',
    sample: <BaseMenu />,
  },
  {
    id: 'context-menu',
    title: 'Context menu',
    detail: 'Right-click a cell for edit, duplicate, and a destructive delete row.',
    sample: <BaseContextMenu />,
  },
  {
    id: 'popover',
    title: 'Popover',
    detail: 'Icon trigger for page display settings, stepping spacing with minus and plus icon buttons.',
    sample: <BasePopover />,
  },
  {
    id: 'dialog',
    title: 'Dialog',
    detail: 'Focused insert confirmation with an icon-only close button in the header. Escape returns focus to the trigger.',
    sample: <BaseDialog />,
  },
  {
    id: 'tooltip',
    title: 'Action bar tooltips',
    detail: 'Icon-only quick actions share one tooltip delay so scanning across buttons reveals descriptions and shortcuts immediately.',
    sample: <BaseTooltip />,
  },
  {
    id: 'search',
    title: 'Expression search',
    detail: 'Expression combobox with a leading search icon and command trigger hints.',
    sample: <BaseExpressionSearch />,
  },
  {
    id: 'tabs',
    title: 'Tabs',
    detail: 'Segmented preview and source tabs with eye and code icons plus shortcut tooltips.',
    sample: <BaseTabs />,
  },
  {
    id: 'width',
    title: 'Page width',
    detail: 'Segmented icon rail for a narrow reading width or the full page width.',
    sample: <BasePageWidth />,
  },
  {
    id: 'checkbox',
    title: 'Checkbox',
    detail: 'A task in a Markdown list with a vector check indicator. Space toggles it.',
    sample: <BaseCheckbox />,
  },
  {
    id: 'disclosure',
    title: 'Disclosure',
    detail: 'Rotating chevron disclosure for the movement guide.',
    sample: <BaseDisclosure />,
  },
  {
    id: 'hover-card',
    title: 'Hover preview',
    detail: 'A symbol previews the expression it would insert. Hover or focus the integral.',
    sample: <BaseHoverCard />,
  },
  {
    id: 'spacing',
    title: 'Cell spacing',
    detail: 'Minus and plus icon steppers with shortcut tooltips, direct number entry, or arrow keys.',
    sample: <BaseSpacing />,
  },
  {
    id: 'shortcuts',
    title: 'Shortcut list',
    detail: 'A long keyboard guide in a bounded scrollport.',
    sample: <BaseShortcutList />,
  },
]

const gallerySections: readonly GallerySection[] = [
  {
    id: 'notebook',
    title: 'Notebook',
    detail: 'Icons, formatting, cell states, and the input controls that sit on the page.',
    specimens: notebookSpecimens,
  },
  {
    id: 'command-palette',
    title: 'Command palette',
    detail: 'A searchable list of notebook actions. The notebook supplies the actions. This shell searches them and reports the one that was chosen.',
    specimens: commandPaletteSpecimens,
  },
  {
    id: 'sidebars',
    title: 'Sidebars',
    detail: 'Lists that sit beside a page. The page list switches which page is open. Chat has its own dock in the next section.',
    specimens: sidebarSpecimens,
  },
  {
    id: 'chat',
    title: 'Chat',
    detail: 'A sidebar dock and a full-screen assistant you can type into. Sending any message returns the same mock reply. Highlighting and context pills show how notebook material attaches to that thread.',
    specimens: chatSpecimens,
  },
  {
    id: 'agent',
    title: 'Agent',
    detail: 'Tool results the assistant can show after a reply.',
    specimens: agentSpecimens,
  },
  {
    id: 'controls',
    title: 'Controls',
    detail: 'Menus, popups, and the rest of the Base UI primitives.',
    specimens: controlSpecimens,
  },
]

const galleryNav: readonly GalleryNavItem[] = [
  { id: 'theme', title: 'Theme' },
  { id: 'notebook', title: 'Notebook' },
  { id: 'command-palette', title: 'Command palette' },
  { id: 'sidebars', title: 'Sidebars' },
  { id: 'chat', title: 'Chat' },
  { id: 'agent', title: 'Agent' },
  { id: 'controls', title: 'Controls' },
]

/** Render one jump link in the section nav. */
function renderGalleryNavLink(item: GalleryNavItem) {
  return (
    <a key={item.id} href={`#${item.id}`}>
      {item.title}
    </a>
  )
}

/** Render one specimen card. */
function renderPrimitiveSpecimen(specimen: PrimitiveSpecimen) {
  return (
    <section className="primitive-row" key={specimen.id} aria-labelledby={`${specimen.id}-heading`}>
      <h3 id={`${specimen.id}-heading`}>{specimen.title}</h3>
      <p className="primitive-row-copy">{specimen.detail}</p>
      {specimen.sample}
    </section>
  )
}

/** Render one named group of specimens. */
function renderGallerySection(section: GallerySection) {
  return (
    <section className="gallery-section" id={section.id} key={section.id} aria-labelledby={`${section.id}-section-heading`}>
      <header className="gallery-section-header">
        <h2 id={`${section.id}-section-heading`}>{section.title}</h2>
        <p>{section.detail}</p>
      </header>
      <div className="primitive-specimens">{section.specimens.map(renderPrimitiveSpecimen)}</div>
    </section>
  )
}

/** Show the theme tokens, then the notebook, command palette, sidebars, chat, agent, and control sections. */
function ComponentLibraryPage() {
  return (
    <Tooltip.Provider delay={220} closeDelay={0}>
      <main className="primitive-gallery">
        <header>
          <h1>Components</h1>
          <p>Theme, notebook chrome, a command palette, page sidebars, working chat surfaces, agent tool cards, and Base UI controls. The chats use mock replies.</p>
        </header>
        <nav className="gallery-nav" aria-label="Component sections">
          {galleryNav.map(renderGalleryNavLink)}
        </nav>
        <div id="theme" className="gallery-anchor">
          <ThemeControls gallery />
        </div>
        {gallerySections.map(renderGallerySection)}
      </main>
    </Tooltip.Provider>
  )
}
