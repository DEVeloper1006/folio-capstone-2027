/**
 * Connect MathLive fields to the navigation system. Contains selection conversion, cached structure reads, geometry lookup, and DOM event installation and cleanup.
 *
 * @file
 */

import type { MathfieldElement } from 'mathlive'
import { getNavigationAction } from './navigation-actions.ts'
import type { CursorSelection } from './navigation-actions.ts'
import { createNavigationState, applyNavigationAction } from './navigation-transition.ts'
import { buildStructure } from './structure.ts'

/** Read MathLive’s first selection range as a fixed anchor and moving focus, preserving backward selection direction. */
function readSelection(mathfield: MathfieldElement): CursorSelection {
  const [start, end] = mathfield.selection.ranges[0]
  return mathfield.selection.direction === 'backward' ? { anchor: end, focus: start } : { anchor: start, focus: end }
}

/** Write anchor and focus into MathLive’s ordered range and direction without changing the formula. */
function applySelection(mathfield: MathfieldElement, selection: CursorSelection) {
  mathfield.selection = {
    ranges: [[Math.min(selection.anchor, selection.focus), Math.max(selection.anchor, selection.focus)]],
    direction: selection.focus < selection.anchor ? 'backward' : 'forward',
  }
}

/** Connect one MathLive field to the navigation rules, cache structure while its LaTeX is unchanged, and return a listener cleanup function. */
export function installNavigation(mathfield: MathfieldElement) {
  let cachedLatex: string | undefined
  let cachedStructure: ReturnType<typeof buildStructure>
  let navigationState = createNavigationState(readSelection(mathfield))

  /** Discard logical selection anchors and vertical return positions after pointer input, formula edits, or focus loss. */
  const resetSelectionHistory = () => {
    navigationState = createNavigationState(readSelection(mathfield))
  }

  /** Build the navigation structure from MathLive’s public element metadata only when the formula changes. */
  const readCachedStructure = () => {
    if (cachedLatex !== mathfield.value) {
      /** Read one cursor offset’s nesting depth and serialized LaTeX from MathLive. */
      const readElementSnapshot = (_: unknown, cursorOffset: number) => {
        const elementInfo = mathfield.getElementInfo(cursorOffset)
        return {
          depth: elementInfo?.depth ?? 0,
          latex: elementInfo?.latex ?? '',
        }
      }

      cachedStructure = buildStructure(Array.from({ length: mathfield.lastOffset + 1 }, readElementSnapshot))
      cachedLatex = mathfield.value
    }
    return cachedStructure
  }

  /** Read the rendered cursor's right boundary; MathLive represents an empty region anchor with a negative-width sentinel rectangle. */
  const getCursorX = (cursorOffset: number) => {
    const elementInfo = mathfield.getElementInfo(cursorOffset)
    if (!elementInfo?.bounds) return undefined
    return elementInfo.bounds.right
  }

  /** Decode the key, apply a matching navigation transition, and prevent MathLive from handling the same event twice. Unhandled keys retain MathLive’s behavior. */
  const handleKeyDown = (event: KeyboardEvent) => {
    if (['Alt', 'Shift', 'Control', 'Meta'].includes(event.key)) return
    const navigationAction = getNavigationAction(event)
    if (!navigationAction || mathfield.mode === 'latex') {
      resetSelectionHistory()
      return
    }

    const currentSelection = readSelection(mathfield)
    if (currentSelection.anchor !== navigationState.selection.anchor || currentSelection.focus !== navigationState.selection.focus) navigationState = createNavigationState(currentSelection)
    const navigationResult = applyNavigationAction(navigationState, navigationAction, { structure: readCachedStructure(), xAt: getCursorX })
    navigationState = navigationResult.state
    if (!navigationResult.handled) return

    event.preventDefault()
    event.stopImmediatePropagation()
    applySelection(mathfield, navigationState.selection)
    const actualSelection = readSelection(mathfield)
    navigationState = {
      ...navigationState,
      selection: actualSelection,
      lastGrowth: navigationState.lastGrowth ? actualSelection : undefined,
    }
  }

  mathfield.addEventListener('keydown', handleKeyDown, { capture: true })
  mathfield.addEventListener('pointerdown', resetSelectionHistory)
  mathfield.addEventListener('input', resetSelectionHistory)
  mathfield.addEventListener('blur', resetSelectionHistory)

  /** Remove every event listener installed for this field. */
  const removeNavigationListeners = () => {
    mathfield.removeEventListener('keydown', handleKeyDown, { capture: true })
    mathfield.removeEventListener('pointerdown', resetSelectionHistory)
    mathfield.removeEventListener('input', resetSelectionHistory)
    mathfield.removeEventListener('blur', resetSelectionHistory)
  }
  return removeNavigationListeners
}
