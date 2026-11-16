/**
 * Connect a React host element to an editable MathLive field. Contains browser-only loading, background preloading, field configuration, repeated spaces, logical-connective aliases, command-key delegation, change reporting, and cleanup.
 *
 * @file
 */

import { useEffect, useRef } from 'react'
import type * as MathLive from 'mathlive'
import type { MathfieldElement } from 'mathlive'
import { installNavigation } from '../navigation/navigation.ts'
import { expandMathfieldAliases, installMathfieldMacros } from './mathfield-macros.ts'

/** Insert one thick space for each spacebar press, including directly beside another space. MathLive’s empty default moves out of the current group and inserts nothing at the top of a formula. */
const repeatedMathSpace = String.raw`\;`

/** Identify the formula, supply its initial LaTeX, and report subsequent edits. The initial value seeds the field once; a new callback does not replace the active formula. */
interface UseMathLiveOptions {
  cellId: string
  initialLatex: string
  onLatexChange: (cellId: string, latex: string) => void
  onEditorKeyDown?: (mathfield: MathfieldElement, event: KeyboardEvent) => boolean
  focusOnMount?: boolean
  /** Accessible name announced for the field. A notebook cell uses “LaTeX cell”. */
  label?: string
  /** Adjust the mounted field once, after its value is set. Used to fit an inline formula to the surrounding text. */
  configureMathfield?: (mathfield: MathfieldElement) => void
}

/** Drop MathLive’s virtual-keyboard shortcut so the field keeps the remaining bindings. */
export function withoutVirtualKeyboardToggle(keybindings: MathfieldElement['keybindings']) {
  /** Exclude MathLive’s virtual-keyboard toggle from the available key bindings. */
  const isAllowedKeybinding = ({ command }: MathfieldElement['keybindings'][number]) => command !== 'toggleVirtualKeyboard'
  return keybindings.filter(isAllowedKeybinding)
}

/** Return the host ref for one MathLive field and manage its browser lifecycle. Use the initial LaTeX once. A new change callback or key handler does not rebuild the active field. */
export function useMathLive({ cellId, initialLatex, onLatexChange, onEditorKeyDown, focusOnMount = false, label = 'LaTeX cell', configureMathfield }: UseMathLiveOptions) {
  const editorHostRef = useRef<HTMLDivElement>(null)
  const initialLatexRef = useRef(initialLatex)
  const onLatexChangeRef = useRef(onLatexChange)
  const editorKeyDownRef = useRef(onEditorKeyDown)
  const labelRef = useRef(label)
  const configureMathfieldRef = useRef(configureMathfield)

  /** Keep the latest change callback, key handler, accessible name, and one-time setup without rebuilding the active MathLive field. */
  function updateEditorHandlers() {
    onLatexChangeRef.current = onLatexChange
    editorKeyDownRef.current = onEditorKeyDown
    labelRef.current = label
    configureMathfieldRef.current = configureMathfield
  }
  useEffect(updateEditorHandlers, [onLatexChange, onEditorKeyDown, label, configureMathfield])

  /** Load the browser-only editor after mounting and remove it when this React cell unmounts. */
  const mountEditor = () => {
    let isDisposed = false
    let mountedMathfield: MathfieldElement | undefined
    let removeNavigationListeners: (() => void) | undefined

    /** Create the MathLive field, insert a thick space for Space, register logical-connective aliases, disable its menu and virtual keyboard, and attach the navigation handler. */
    const initializeEditor = ({ MathfieldElement }: typeof MathLive) => {
      if (isDisposed) return

      MathfieldElement.fontsDirectory = null
      const mathfield = new MathfieldElement()
      mountedMathfield = mathfield
      mathfield.setAttribute('aria-label', labelRef.current)

      /** Report this field’s current LaTeX through the latest callback after an input event. Aliases such as `\or` are stored as the commands KaTeX draws. */
      const reportLatexChange = () => onLatexChangeRef.current(cellId, expandMathfieldAliases(mathfield.value))

      mathfield.addEventListener('input', reportLatexChange)
      mathfield.mathModeSpace = repeatedMathSpace
      editorHostRef.current?.appendChild(mathfield)
      if (mathfield.isConnected) installMathfieldMacros(mathfield)
      mathfield.value = initialLatexRef.current
      mathfield.mathVirtualKeyboardPolicy = 'manual'
      mathfield.menuItems = []

      mathfield.keybindings = withoutVirtualKeyboardToggle(mathfield.keybindings)
      /** Give cell commands the first opportunity to consume a key before mathematical navigation. */
      function handleEditorKeyDown(event: KeyboardEvent) {
        return editorKeyDownRef.current?.(mathfield, event) ?? false
      }
      removeNavigationListeners = installNavigation(mathfield, handleEditorKeyDown)
      if (focusOnMount) mathfield.focus()
      configureMathfieldRef.current?.(mathfield)
    }

    // MathLive's editable field requires the browser DOM.
    void import('mathlive').then(initializeEditor)

    /** Cancel pending initialization, detach navigation listeners, and remove the mounted field. */
    const unmountEditor = () => {
      isDisposed = true
      removeNavigationListeners?.()
      mountedMathfield?.remove()
    }
    return unmountEditor
  }

  useEffect(mountEditor, [cellId, focusOnMount])

  return editorHostRef
}

/** Download the MathLive module after the import callback runs. */
function loadMathLive() {
  void import('mathlive')
}

let didSchedulePreload = false

/** Download MathLive once, after the first paint. Activating a cell reuses this cached module, and the server never loads it. */
export function preloadMathLive() {
  if (didSchedulePreload) {
    /** Leave the shared download in place when another cell subscribes. */
    function keepScheduledPreload() {}
    return keepScheduledPreload
  }
  didSchedulePreload = true

  if (typeof requestIdleCallback !== 'function') {
    const timeoutId = setTimeout(loadMathLive, 1)
    /** Cancel a preload that was scheduled with a timer. */
    function cancelTimeoutPreload() {
      clearTimeout(timeoutId)
    }
    return cancelTimeoutPreload
  }

  const idleId = requestIdleCallback(loadMathLive, { timeout: 1500 })
  /** Cancel a preload that is still waiting for idle time. */
  function cancelIdlePreload() {
    cancelIdleCallback(idleId)
    didSchedulePreload = false
  }
  return cancelIdlePreload
}
