/**
 * Share the sample notebook actions used by every primitive column. Contains expression searches, menu actions, and shortcut lines.
 *
 * @file
 */

/** Name one insertable expression by its search value, visible label, and the symbol shown beside it. */
export interface ExpressionCommand {
  value: string
  label: string
  symbol: string
}

/** List the expression templates a command search should offer. */
export const expressionCommands: readonly ExpressionCommand[] = [
  { value: 'frac', label: 'Fraction', symbol: 'a/b' },
  { value: 'sqrt', label: 'Square root', symbol: '√' },
  { value: 'int', label: 'Integral', symbol: '∫' },
  { value: 'sum', label: 'Sum', symbol: 'Σ' },
  { value: 'lim', label: 'Limit', symbol: 'lim' },
  { value: 'matrix', label: 'Matrix', symbol: '[ ]' },
]

/** List keyboard hints that belong in a scrolling shortcut guide. */
export const shortcutLines: readonly string[] = [
  'Arrow keys move inside a structure',
  'Option + arrows jump a term or leave a structure',
  'Shift + arrows grow the selection',
  'Tab visits the next placeholder',
  '/ in an empty region searches templates',
  'Escape closes a menu without editing',
  'Home and End stay in the current region',
  'Command + Enter finishes a Markdown edit',
]
