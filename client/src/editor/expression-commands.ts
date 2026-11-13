/**
 * Define searchable expression templates and one level of variants. Contains local command IDs, labels, symbols, keywords, and MathLive LaTeX placeholders.
 *
 * @file
 */

/** Describe one independently searchable template that expands into editable math when inserted. */
export interface ExpressionCommand {
  id: string
  label: string
  symbol: string
  keywords: readonly string[]
  latex: string
}

/** Add one level of insertable variants; child definitions cannot declare more variants. */
export interface ExpressionCommandGroup extends ExpressionCommand {
  variants?: readonly ExpressionCommand[]
}

/** Keep the initial catalog local and immutable; aliases and variants share the same insertion definitions. */
export const expressionCommands: readonly ExpressionCommandGroup[] = [
  {
    id: 'fraction',
    label: 'Fraction',
    symbol: 'a/b',
    keywords: ['frac', 'fraction', 'divide', 'ratio'],
    latex: String.raw`\frac{#?}{#?}`,
    variants: [{ id: 'binomial', label: 'Binomial coefficient', symbol: '(ⁿₖ)', keywords: ['binom', 'choose', 'binomial'], latex: String.raw`\binom{#?}{#?}` }],
  },
  {
    id: 'root',
    label: 'Square root',
    symbol: '√',
    keywords: ['sqrt', 'root', 'radical', 'square root'],
    latex: String.raw`\sqrt{#?}`,
    variants: [
      { id: 'cube-root', label: 'Cube root', symbol: '∛', keywords: ['cbrt', 'cube root'], latex: String.raw`\sqrt[3]{#?}` },
      { id: 'nth-root', label: 'Nth root', symbol: 'ⁿ√', keywords: ['nth root', 'indexed root'], latex: String.raw`\sqrt[#?]{#?}` },
    ],
  },
  {
    id: 'sum',
    label: 'Summation',
    symbol: '∑',
    keywords: ['sum', 'summation', 'sigma', 'big operators'],
    latex: String.raw`\sum_{#?}^{#?}#?`,
    variants: [
      { id: 'product', label: 'Product', symbol: '∏', keywords: ['prod', 'product', 'big pi'], latex: String.raw`\prod_{#?}^{#?}#?` },
      { id: 'coproduct', label: 'Coproduct', symbol: '∐', keywords: ['coprod', 'coproduct'], latex: String.raw`\coprod_{#?}^{#?}#?` },
      { id: 'conjunction', label: 'Big conjunction', symbol: '⋀', keywords: ['bigwedge', 'conjunction', 'and'], latex: String.raw`\bigwedge_{#?}^{#?}#?` },
      { id: 'disjunction', label: 'Big disjunction', symbol: '⋁', keywords: ['bigvee', 'disjunction', 'or'], latex: String.raw`\bigvee_{#?}^{#?}#?` },
    ],
  },
  {
    id: 'integral',
    label: 'Integral',
    symbol: '∫',
    keywords: ['int', 'integral', 'integrate', 'integrand'],
    latex: String.raw`\int #?\,\mathrm{d}#?`,
    variants: [
      { id: 'definite-integral', label: 'Definite integral', symbol: '∫ₐᵇ', keywords: ['defint', 'definite integral', 'bounded integral'], latex: String.raw`\int_{#?}^{#?}#?\,\mathrm{d}#?` },
      { id: 'double-integral', label: 'Double integral', symbol: '∬', keywords: ['iint', 'double integral'], latex: String.raw`\iint #?\,\mathrm{d}#?\,\mathrm{d}#?` },
      { id: 'triple-integral', label: 'Triple integral', symbol: '∭', keywords: ['iiint', 'triple integral'], latex: String.raw`\iiint #?\,\mathrm{d}#?\,\mathrm{d}#?\,\mathrm{d}#?` },
      { id: 'line-integral', label: 'Line integral', symbol: '∫꜀', keywords: ['line integral', 'path integral'], latex: String.raw`\int_{#?}#?\cdot\mathrm{d}#?` },
      { id: 'contour-integral', label: 'Contour integral', symbol: '∮', keywords: ['oint', 'contour integral', 'closed line integral'], latex: String.raw`\oint_{#?}#?\,\mathrm{d}#?` },
    ],
  },
]
