/**
 * Show the Base UI primitives used for notebook chrome, pairing compact Lucide icons with tooltips and shortcut hints. Contains menus, popups, combobox search, tabs, segmented width, formatting toolbar, number field, and scrolling.
 *
 * @file
 */

import { useState } from 'react'
import { Checkbox } from '@base-ui/react/checkbox'
import { Collapsible } from '@base-ui/react/collapsible'
import { Combobox } from '@base-ui/react/combobox'
import { ContextMenu } from '@base-ui/react/context-menu'
import { Dialog } from '@base-ui/react/dialog'
import { Menu } from '@base-ui/react/menu'
import { NumberField } from '@base-ui/react/number-field'
import { Popover } from '@base-ui/react/popover'
import { PreviewCard } from '@base-ui/react/preview-card'
import { ScrollArea } from '@base-ui/react/scroll-area'
import { Tabs } from '@base-ui/react/tabs'
import { Toggle } from '@base-ui/react/toggle'
import { ToggleGroup } from '@base-ui/react/toggle-group'
import { Toolbar } from '@base-ui/react/toolbar'
import {
  BoldIcon,
  CellEditingIcon,
  CellSelectedIcon,
  CloseIcon,
  CodeIcon,
  CopyIcon,
  DeleteIcon,
  DisclosureChevronIcon,
  DisplayMathIcon,
  FullWidthIcon,
  HeadingIcon,
  ItalicIcon,
  KeyboardIcon,
  LinkIcon,
  ListIcon,
  MarkdownIcon,
  MathIcon,
  MinusIcon,
  MoreActionsIcon,
  PlusIcon,
  PreviewIcon,
  QuoteIcon,
  RegularWidthIcon,
  SearchIcon,
  SettingsIcon,
  SourceIcon,
} from '#/component-library/icons/folio-icons.tsx'
import { IconTooltip } from './icon-tooltip.tsx'
import type { ExpressionCommand } from './primitive-samples.ts'
import { expressionCommands, shortcutLines } from './primitive-samples.ts'

/** Remember the latest menu action so a click has a visible result. */
function useActionStatus() {
  const [action, setAction] = useState('None yet')

  /** Store the action name carried on the activated item. */
  function rememberAction(event: { currentTarget: EventTarget | null }) {
    const target = event.currentTarget
    if (!(target instanceof HTMLElement)) return
    const nextAction = target.dataset.action
    if (nextAction) setAction(nextAction)
  }

  return { action, rememberAction }
}

/** Open a cell action menu from a compact overflow icon button with shortcut hints inside the menu. */
export function BaseMenu() {
  const { action, rememberAction } = useActionStatus()

  return (
    <div>
      <Menu.Root>
        <IconTooltip label="Cell actions">
          <Menu.Trigger className="primitive-icon-button" aria-label="Cell actions">
            <MoreActionsIcon />
          </Menu.Trigger>
        </IconTooltip>
        <Menu.Portal>
          <Menu.Positioner sideOffset={6} align="start">
            <Menu.Popup className="primitive-popup">
              <Menu.Item className="primitive-item" data-action="Add math cell" onClick={rememberAction}>
                <span className="primitive-item-label">
                  <MathIcon /> Add math cell
                </span>
                <span className="primitive-kbd">Opt Cmd M</span>
              </Menu.Item>
              <Menu.Item className="primitive-item" data-action="Add Markdown cell" onClick={rememberAction}>
                <span className="primitive-item-label">
                  <MarkdownIcon /> Add Markdown cell
                </span>
                <span className="primitive-kbd">Opt Cmd E</span>
              </Menu.Item>
              <Menu.Separator className="primitive-separator" />
              <Menu.Item className="primitive-item" data-action="Copy LaTeX" onClick={rememberAction}>
                <span className="primitive-item-label">
                  <CopyIcon /> Copy LaTeX
                </span>
                <span className="primitive-kbd">Cmd C</span>
              </Menu.Item>
            </Menu.Popup>
          </Menu.Positioner>
        </Menu.Portal>
      </Menu.Root>
      <p className="primitive-status">Last action: {action}</p>
      <div className="primitive-item primitive-item-current">
        <span className="primitive-item-label">
          <MathIcon /> Add math cell
        </span>
        <span className="primitive-kbd">Opt Cmd M</span>
      </div>
    </div>
  )
}

/** Open cell actions with icons and shortcuts from a right-click. */
export function BaseContextMenu() {
  const { action, rememberAction } = useActionStatus()

  return (
    <div>
      <ContextMenu.Root>
        <ContextMenu.Trigger className="primitive-surface">Right-click this cell</ContextMenu.Trigger>
        <ContextMenu.Portal>
          <ContextMenu.Positioner>
            <ContextMenu.Popup className="primitive-popup">
              <ContextMenu.Item className="primitive-item" data-action="Edit cell" onClick={rememberAction}>
                <span className="primitive-item-label">
                  <CellEditingIcon /> Edit
                </span>
                <span className="primitive-kbd">Enter</span>
              </ContextMenu.Item>
              <ContextMenu.Item className="primitive-item" data-action="Duplicate cell" onClick={rememberAction}>
                <span className="primitive-item-label">
                  <CopyIcon /> Duplicate
                </span>
                <span className="primitive-kbd">Cmd D</span>
              </ContextMenu.Item>
              <ContextMenu.Separator className="primitive-separator" />
              <ContextMenu.Item className="primitive-item primitive-item-danger" data-action="Delete cell" onClick={rememberAction}>
                <span className="primitive-item-label">
                  <DeleteIcon /> Delete
                </span>
                <span className="primitive-kbd">Del</span>
              </ContextMenu.Item>
            </ContextMenu.Popup>
          </ContextMenu.Positioner>
        </ContextMenu.Portal>
      </ContextMenu.Root>
      <p className="primitive-status">Last action: {action}</p>
    </div>
  )
}

/** Edit cell spacing from a compact display-settings icon trigger. */
export function BasePopover() {
  return (
    <Popover.Root>
      <IconTooltip label="Page display">
        <Popover.Trigger className="primitive-icon-button" aria-label="Page display">
          <SettingsIcon />
        </Popover.Trigger>
      </IconTooltip>
      <Popover.Portal>
        <Popover.Positioner sideOffset={6} align="start">
          <Popover.Popup className="primitive-popup primitive-popover-panel">
            <span className="primitive-field-label">Cell spacing (px)</span>
            <NumberField.Root defaultValue={16} min={0} step={4}>
              <NumberField.Group className="primitive-number">
                <NumberField.Decrement className="primitive-icon-button" aria-label="Decrease cell spacing">
                  <MinusIcon />
                </NumberField.Decrement>
                <NumberField.Input className="primitive-input" aria-label="Cell spacing" />
                <NumberField.Increment className="primitive-icon-button" aria-label="Increase cell spacing">
                  <PlusIcon />
                </NumberField.Increment>
              </NumberField.Group>
            </NumberField.Root>
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  )
}

/** Confirm insertion of a display-math block with an icon-labeled primary button and a compact close button. */
export function BaseDialog() {
  return (
    <Dialog.Root>
      <Dialog.Trigger className="primitive-trigger primitive-trigger-primary">
        <DisplayMathIcon /> Insert math
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Backdrop className="primitive-backdrop" />
        <Dialog.Popup className="primitive-dialog">
          <div className="primitive-dialog-header">
            <Dialog.Title className="primitive-dialog-title">Insert display math</Dialog.Title>
            <IconTooltip label="Close" shortcut="Esc">
              <Dialog.Close className="primitive-icon-button primitive-icon-quiet" aria-label="Close dialog">
                <CloseIcon />
              </Dialog.Close>
            </IconTooltip>
          </div>
          <Dialog.Description>Places a display block at the cursor. Escape or Close returns focus to the trigger.</Dialog.Description>
          <div className="primitive-dialog-actions">
            <Dialog.Close className="primitive-trigger primitive-trigger-primary">
              <PlusIcon /> Insert block
            </Dialog.Close>
          </div>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  )
}

/** Show icon-only triggers whose labels and shortcuts appear on hover or focus. */
export function BaseTooltip() {
  return (
    <div className="primitive-bar">
      <IconTooltip label="Search expressions" shortcut="/">
        <button type="button" className="primitive-icon-button" aria-label="Search expressions">
          <SearchIcon />
        </button>
      </IconTooltip>
      <IconTooltip label="Add math cell" shortcut="Opt Cmd M">
        <button type="button" className="primitive-icon-button" aria-label="Add math cell">
          <MathIcon />
        </button>
      </IconTooltip>
      <IconTooltip label="Add Markdown cell" shortcut="Opt Cmd E">
        <button type="button" className="primitive-icon-button" aria-label="Add Markdown cell">
          <MarkdownIcon />
        </button>
      </IconTooltip>
      <IconTooltip label="Keyboard shortcuts" shortcut="?">
        <button type="button" className="primitive-icon-button" aria-label="Keyboard shortcuts">
          <KeyboardIcon />
        </button>
      </IconTooltip>
    </div>
  )
}

/** Filter expression templates with a leading search icon inside the input field. */
export function BaseExpressionSearch() {
  /** Render one template that survived the current query. */
  function renderExpression(command: ExpressionCommand) {
    return (
      <Combobox.Item key={command.value} className="primitive-item" value={command}>
        <span className="primitive-item-label">
          <span className="primitive-command-symbol">{command.symbol}</span>
          {command.label}
        </span>
        <span className="primitive-kbd">/{command.value}</span>
      </Combobox.Item>
    )
  }

  return (
    <Combobox.Root items={expressionCommands}>
      <div className="primitive-search-box">
        <SearchIcon />
        <Combobox.Input className="primitive-search-input" placeholder="Search expressions…" aria-label="Search expressions" />
      </div>
      <Combobox.Portal>
        <Combobox.Positioner sideOffset={6} align="start">
          <Combobox.Popup className="primitive-popup">
            <Combobox.Empty className="primitive-empty">No matching template</Combobox.Empty>
            <Combobox.List>{renderExpression}</Combobox.List>
          </Combobox.Popup>
        </Combobox.Positioner>
      </Combobox.Portal>
    </Combobox.Root>
  )
}

/** Switch a Markdown cell between rendered preview and raw source using icon-paired tabs. */
export function BaseTabs() {
  return (
    <Tabs.Root defaultValue="preview">
      <Tabs.List className="primitive-segmented" aria-label="Markdown cell">
        <IconTooltip label="Rendered preview" shortcut="Cmd E">
          <Tabs.Tab className="primitive-segment" value="preview">
            <PreviewIcon /> Preview
          </Tabs.Tab>
        </IconTooltip>
        <IconTooltip label="Markdown source" shortcut="Enter">
          <Tabs.Tab className="primitive-segment" value="source">
            <SourceIcon /> Source
          </Tabs.Tab>
        </IconTooltip>
      </Tabs.List>
      <Tabs.Panel className="primitive-panel type-reading" value="preview">
        A notebook needs the why as well as the working.
      </Tabs.Panel>
      <Tabs.Panel className="primitive-panel type-code" value="source">
        ## Make room for the reasoning
      </Tabs.Panel>
    </Tabs.Root>
  )
}

/** Choose regular or full page width with compact icon toggles and tooltips. */
export function BasePageWidth() {
  return (
    <ToggleGroup className="primitive-segmented" defaultValue={['regular']} aria-label="Page width">
      <IconTooltip label="Regular reading width">
        <Toggle className="primitive-icon-button primitive-segment-icon" value="regular" aria-label="Regular width">
          <RegularWidthIcon />
        </Toggle>
      </IconTooltip>
      <IconTooltip label="Full page width">
        <Toggle className="primitive-icon-button primitive-segment-icon" value="full" aria-label="Full width">
          <FullWidthIcon />
        </Toggle>
      </IconTooltip>
    </ToggleGroup>
  )
}

/** Toggle Markdown inline marks and block structures in a compact icon-only formatting bar with shortcut tooltips. */
export function BaseToolbar() {
  return (
    <Toolbar.Root className="primitive-toolbar-bar" aria-label="Markdown formatting">
      <ToggleGroup className="primitive-toolbar-group" multiple aria-label="Inline marks">
        <IconTooltip label="Bold" shortcut="Cmd B">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="bold" aria-label="Bold">
            <BoldIcon />
          </Toggle>
        </IconTooltip>
        <IconTooltip label="Italic" shortcut="Cmd I">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="italic" aria-label="Italic">
            <ItalicIcon />
          </Toggle>
        </IconTooltip>
        <IconTooltip label="Inline code" shortcut="Cmd E">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="code" aria-label="Inline code">
            <CodeIcon />
          </Toggle>
        </IconTooltip>
        <IconTooltip label="Inline math" shortcut="Cmd M">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="math" aria-label="Inline math">
            <MathIcon />
          </Toggle>
        </IconTooltip>
      </ToggleGroup>
      <Toolbar.Separator className="primitive-toolbar-divider" />
      <ToggleGroup className="primitive-toolbar-group" multiple aria-label="Structure">
        <IconTooltip label="Section heading" shortcut="Cmd Opt 2">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="heading" aria-label="Heading">
            <HeadingIcon />
          </Toggle>
        </IconTooltip>
        <IconTooltip label="Bullet list" shortcut="Cmd Shift 8">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="list" aria-label="Bullet list">
            <ListIcon />
          </Toggle>
        </IconTooltip>
        <IconTooltip label="Blockquote" shortcut="Cmd Shift .">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="quote" aria-label="Blockquote">
            <QuoteIcon />
          </Toggle>
        </IconTooltip>
        <IconTooltip label="Insert link" shortcut="Cmd K">
          <Toggle className="primitive-icon-button primitive-icon-quiet" value="link" aria-label="Insert link">
            <LinkIcon />
          </Toggle>
        </IconTooltip>
      </ToggleGroup>
    </Toolbar.Root>
  )
}

/** Check a task in a Markdown list with a crisp vector checkmark. */
export function BaseCheckbox() {
  return (
    <label className="primitive-check">
      <Checkbox.Root className="primitive-checkbox" defaultChecked>
        <Checkbox.Indicator className="primitive-checkbox-indicator">
          <CellSelectedIcon />
        </Checkbox.Indicator>
      </Checkbox.Root>
      Define assumptions
    </label>
  )
}

/** Disclose the movement summary with a rotating chevron and keyboard icon. */
export function BaseDisclosure() {
  return (
    <Collapsible.Root>
      <Collapsible.Trigger className="primitive-disclosure-trigger">
        <DisclosureChevronIcon />
        <KeyboardIcon />
        Movement keys
      </Collapsible.Trigger>
      <Collapsible.Panel className="primitive-panel">Arrow keys enter a numerator or superscript, then leave the structure horizontally.</Collapsible.Panel>
    </Collapsible.Root>
  )
}

/** Preview an expression before it is inserted. */
export function BaseHoverCard() {
  return (
    <PreviewCard.Root>
      <PreviewCard.Trigger className="primitive-symbol" aria-label="Integral">
        ∫
      </PreviewCard.Trigger>
      <PreviewCard.Portal>
        <PreviewCard.Positioner sideOffset={6}>
          <PreviewCard.Popup className="primitive-popup">Integral. Search with /int.</PreviewCard.Popup>
        </PreviewCard.Positioner>
      </PreviewCard.Portal>
    </PreviewCard.Root>
  )
}

/** Change cell spacing by icon step buttons with tooltips, typing, or arrow keys. */
export function BaseSpacing() {
  return (
    <NumberField.Root defaultValue={16} min={0} max={64} step={4}>
      <NumberField.Group className="primitive-number">
        <IconTooltip label="Decrease spacing" shortcut="Down">
          <NumberField.Decrement className="primitive-icon-button" aria-label="Decrease cell spacing">
            <MinusIcon />
          </NumberField.Decrement>
        </IconTooltip>
        <NumberField.Input className="primitive-input" aria-label="Cell spacing" />
        <IconTooltip label="Increase spacing" shortcut="Up">
          <NumberField.Increment className="primitive-icon-button" aria-label="Increase cell spacing">
            <PlusIcon />
          </NumberField.Increment>
        </IconTooltip>
      </NumberField.Group>
    </NumberField.Root>
  )
}

/** Scroll a long shortcut guide. */
export function BaseShortcutList() {
  /** Render one shortcut line inside the scrollport. */
  function renderShortcut(line: string) {
    return <p key={line}>{line}</p>
  }

  return (
    <ScrollArea.Root className="primitive-scroll">
      <ScrollArea.Viewport>
        <ScrollArea.Content>{shortcutLines.map(renderShortcut)}</ScrollArea.Content>
      </ScrollArea.Viewport>
      <ScrollArea.Scrollbar>
        <ScrollArea.Thumb />
      </ScrollArea.Scrollbar>
    </ScrollArea.Root>
  )
}
