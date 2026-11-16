/**
 * Render stored LaTeX consistently in notebook cells, expression popups, and inline previews. Contains the shared KaTeX configuration and a static presentation component; editing stays in MathLive.
 *
 * @file
 */

import katex from 'katex'
import { previewMacros } from '#/editor/mathlive/mathfield-macros'

/** Render the same macros and error fallback everywhere, with display notation for cells and inline notation for sentences. */
export function renderLatexMarkup(latex: string, displayMode = true) {
  return katex.renderToString(latex, { displayMode, throwOnError: false, strict: 'ignore', output: 'htmlAndMathml', macros: { ...previewMacros } })
}

/** Show a formula without editor state or cell chrome. Display previews share the notebook's math size; inline previews inherit their surrounding text size. */
export function MathPreview({ latex, display = true, className = '' }: { latex: string; display?: boolean; className?: string }) {
  return <span className={`math-preview${display ? ' is-display' : ''} ${className}`} dangerouslySetInnerHTML={{ __html: renderLatexMarkup(latex, display) }} />
}
