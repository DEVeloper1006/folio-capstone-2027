/**
 * Add command aliases MathLive leaves undefined. Contains the logical-connective aliases, the installer that keeps MathLive’s own macros, and the expansion used when a formula is stored.
 *
 * @file
 */

import type { MathfieldElement } from 'mathlive'

/**
 * Expand a typed command to a symbol MathLive already draws. `\or` is logical disjunction and `\and` is logical conjunction. MathLive’s macro table comments both names out, so `\or` otherwise matches only `\originalof` and `\ordinarycolon`. The bare words `or` and `and` are separate shortcuts and
 * do not apply once a backslash has been typed.
 */
const mathfieldMacroAliases = {
  or: String.raw`\lor`,
  and: String.raw`\land`,
} as const

/** Add the aliases to one mounted field. MathLive drops its built-in macros when this property is assigned without them. */
export function installMathfieldMacros(mathfield: MathfieldElement) {
  mathfield.macros = { ...mathfield.macros, ...mathfieldMacroAliases }
}

/** Replace aliases with the commands KaTeX draws. The field keeps `\or` so the command popup can offer it; a stored note uses `\lor`. */
export function expandMathfieldAliases(latex: string) {
  return latex.replaceAll(/\\or(?![a-zA-Z])/g, String.raw`\lor`).replaceAll(/\\and(?![a-zA-Z])/g, String.raw`\land`)
}

/** Render MathLive's unfilled slots in KaTeX without changing the editable LaTeX stored in the notebook. */
export const previewMacros = { '\\placeholder': String.raw`\textcolor{gray}{\square}\phantom{#1}` }
