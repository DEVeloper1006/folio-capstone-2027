/**
 * Connect a React host element to an editable MathLive field. Contains browser-only loading, field configuration, command-key delegation, change reporting, and cleanup.
 *
 * @file
 */

import { useEffect, useRef } from 'react'
import type * as MathLive from 'mathlive'
import type { MathfieldElement } from 'mathlive'
import { installNavigation } from '../navigation/navigation.ts'

/** Identify the notebook cell, supply its initial formula, and report subsequent LaTeX edits. The initial value seeds the field once; parent updates do not replace the active formula. */
interface UseMathLiveOptions {
  cellId: number
  initialLatex: string
  onLatexChange: (cellId: number, latex: string) => void
  onEditorKeyDown?: (mathfield: MathfieldElement, event: KeyboardEvent) => boolean
}

/** Return the host ref for one MathLive field and manage its browser lifecycle. Use the initial LaTeX once; report edits without replacing the active field. */
export function useMathLive({ cellId, initialLatex, onLatexChange, onEditorKeyDown }: UseMathLiveOptions) {
  const editorHostRef = useRef<HTMLDivElement>(null)
  const initialLatexRef = useRef(initialLatex)
  const editorKeyDownRef = useRef(onEditorKeyDown)

  /** Update command delegation without rebuilding the active MathLive field when local menu state changes. */
  function updateKeyHandler() {
    editorKeyDownRef.current = onEditorKeyDown
  }
  useEffect(updateKeyHandler, [onEditorKeyDown])

  /** Load the browser-only editor after mounting and remove it when this React cell unmounts. */
  const mountEditor = () => {
    let isDisposed = false
    let mountedMathfield: MathfieldElement | undefined
    let removeNavigationListeners: (() => void) | undefined

    /** Create the MathLive field, disable its menu and virtual keyboard, and attach the navigation handler. */
    const initializeEditor = ({ MathfieldElement }: typeof MathLive) => {
      if (isDisposed) return

      MathfieldElement.fontsDirectory = null
      const mathfield = new MathfieldElement()
      mountedMathfield = mathfield
      mathfield.setAttribute('aria-label', `LaTeX cell ${cellId + 1}`)

      /** Report this cell’s current LaTeX to the notebook after an input event. */
      const reportLatexChange = () => onLatexChange(cellId, mathfield.value)

      mathfield.addEventListener('input', reportLatexChange)
      editorHostRef.current?.appendChild(mathfield)
      mathfield.value = initialLatexRef.current
      mathfield.mathVirtualKeyboardPolicy = 'manual'
      mathfield.menuItems = []

      /** Exclude MathLive’s virtual-keyboard toggle from the available key bindings. */
      const isAllowedKeybinding = ({ command }: MathfieldElement['keybindings'][number]) => command !== 'toggleVirtualKeyboard'

      mathfield.keybindings = mathfield.keybindings.filter(isAllowedKeybinding)
      /** Give cell commands the first opportunity to consume a key before mathematical navigation. */
      function handleEditorKeyDown(event: KeyboardEvent) {
        return editorKeyDownRef.current?.(mathfield, event) ?? false
      }
      removeNavigationListeners = installNavigation(mathfield, handleEditorKeyDown)
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

  useEffect(mountEditor, [cellId, onLatexChange])

  return editorHostRef
}
