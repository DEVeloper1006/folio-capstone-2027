/**
 * Expose the editor's MathLive integration, command aliases, expression commands, sample expressions, and on-demand LaTeX conversion.
 *
 * @file
 */

import type { LatexConverter } from '#/math/latex-ast.ts'

/** Load the shared converter in the browser when the first expression needs a semantic tree. */
export async function loadLatexConverter(): Promise<LatexConverter> {
  const url = new URL(import.meta.env.BASE_URL + 'dist/latex-ast.js', document.baseURI).href
  await import(/* @vite-ignore */ url)
  return (globalThis as typeof globalThis & { folioLatex: LatexConverter }).folioLatex
}

export { preloadMathLive, useMathLive } from './mathlive/use-mathlive.ts'
export { expandMathfieldAliases } from './mathlive/mathfield-macros.ts'
export { useExpressionCommands } from './commands/use-expression-commands.ts'
export type { CommandMatch } from './commands/expression-command-search.ts'
export { sampleExpressions } from './samples/sample-expressions.ts'
