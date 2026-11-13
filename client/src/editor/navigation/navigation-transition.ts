/**
 * Apply navigation rule results to cursor selections. Contains transition state construction, native fallback, logical focus dispatch, and shared Shift-selection handling for simple destinations.
 *
 * @file
 */

import type { CursorSelection, NavigationAction } from './navigation-actions.ts'
import { navigationRules, resolveRule } from './navigation-rules.ts'
import type { NavigationRule, NavigationState } from './navigation-rules.ts'
import type { Structure } from '../structure/structure.ts'

/** Provide the structure and cursor geometry needed for a transition. An optional rule list replaces the default registry; unavailable horizontal coordinates are reported as undefined. */
export interface NavigationContext {
  structure: Structure
  xAt: (position: number) => number | undefined
  rules?: readonly NavigationRule[]
}

/** Return the next navigation state and whether a rule handled the action. When handled is false, the integration leaves the keyboard event to MathLive. */
export interface NavigationResult {
  handled: boolean
  state: NavigationState
}

/** Start navigation from the supplied anchor and focus with no selection-growth history. */
export function createNavigationState(selection: CursorSelection): NavigationState {
  return { selection, history: [] }
}

/** Resolve the action against the rule registry and compute the next selection. Keep the anchor for Shift movement; return handled false when no rule applies. */
export function applyNavigationAction(navigationState: NavigationState, navigationAction: NavigationAction, navigationContext: NavigationContext): NavigationResult {
  const ruleResult = resolveRule(
    navigationAction.name,
    {
      structure: navigationContext.structure,
      state: navigationState,
      position: navigationState.logicalSelection?.focus ?? navigationState.selection.focus,
      xAt: navigationContext.xAt,
      extend: navigationAction.extend,
    },
    navigationContext.rules ?? navigationRules,
  )

  if (ruleResult === undefined) {
    return {
      handled: false,
      state: createNavigationState(navigationState.selection),
    }
  }
  if (typeof ruleResult !== 'number') return { handled: true, state: ruleResult }

  return {
    handled: true,
    state: createNavigationState({
      anchor: navigationAction.extend ? navigationState.selection.anchor : ruleResult,
      focus: ruleResult,
    }),
  }
}
