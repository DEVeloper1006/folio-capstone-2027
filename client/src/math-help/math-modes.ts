/**
 * Define subject modes and validate declarative notation from config or generated drafts. Reuse the earlier app's single-argument #1 contract; never install executable commands or silently repair generated notation.
 *
 * @file
 */
import katex from 'katex'

export interface MathNotation {
  key: string
  label: string
  latex: string
}
export interface MathMode {
  id: string
  title: string
  summary: string
  bindings: MathNotation[]
}
export interface MathPreferences {
  model: string
  default_mode: string
  suggest_modes: boolean
  modes: MathMode[]
}

export const builtinModes: MathMode[] = [
  { id: 'general', title: 'General math', summary: 'Ask for missing assumptions and help the learner choose one operation. Do not assume a subject.', bindings: [] },
  {
    id: 'algebra',
    title: 'Algebra',
    summary: 'Equations, inequalities, factoring, and functions. Preserve equivalence and state restrictions.',
    bindings: [
      { key: 's', label: 'Square root', latex: '\\sqrt{#1}' },
      { key: 'a', label: 'Absolute value', latex: '\\left|#1\\right|' },
    ],
  },
  {
    id: 'calculus',
    title: 'Calculus',
    summary: 'Limits, derivatives, integrals, and series. State variables, domains, and constants of integration when relevant.',
    bindings: [
      { key: 'd', label: 'Derivative with respect to x', latex: '\\frac{d}{dx}\\left(#1\\right)' },
      { key: 'i', label: 'Integral with respect to x', latex: '\\int #1\\,dx' },
    ],
  },
  {
    id: 'linalg',
    title: 'Linear algebra',
    summary: 'Vectors, matrices, systems, and linear transformations. Check dimensions and distinguish scalars from vectors.',
    bindings: [
      { key: 'n', label: 'Norm', latex: '\\left\\|#1\\right\\|' },
      { key: 't', label: 'Transpose', latex: '\\left(#1\\right)^{T}' },
    ],
  },
  {
    id: 'proof',
    title: 'Proofs and discrete math',
    summary: 'Logic, sets, induction, and proof structure. Separate assumptions from conclusions and justify one inference.',
    bindings: [
      { key: 'n', label: 'Negation', latex: '\\neg\\left(#1\\right)' },
      { key: 'p', label: 'Power set', latex: '\\mathcal{P}\\left(#1\\right)' },
    ],
  },
  {
    id: 'probability',
    title: 'Probability and statistics',
    summary: 'Random variables, distributions, inference, and uncertainty. State independence assumptions and distinguish a sample from a population.',
    bindings: [
      { key: 'e', label: 'Expectation', latex: '\\mathbb{E}\\left[#1\\right]' },
      { key: 'v', label: 'Variance', latex: '\\operatorname{Var}\\left(#1\\right)' },
    ],
  },
  {
    id: 'geometry',
    title: 'Geometry and trigonometry',
    summary: 'Shapes, angles, coordinates, and identities. Track units and geometric assumptions.',
    bindings: [
      { key: 's', label: 'Sine', latex: '\\sin\\left(#1\\right)' },
      { key: 'c', label: 'Cosine', latex: '\\cos\\left(#1\\right)' },
    ],
  },
]
export const defaultMathPreferences: MathPreferences = { model: 'qwen3.5:4b', default_mode: 'general', suggest_modes: true, modes: [] }

/** Require a plain JSON record without trusting model or config types. */
export function mathRecord(value: unknown, name: string): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${name} must be an object.`)
  return Object.fromEntries(Object.entries(value))
}
/** Reject nonprinting controls while retaining ordinary tabs and newlines. */
function isControl(character: string) {
  const code = character.charCodeAt(0)
  return (code < 32 && code !== 9 && code !== 10) || code === 127
}
/** Require bounded printable text before displaying or sending it to the model. */
export function mathText(value: unknown, name: string, limit: number): string {
  if (typeof value !== 'string' || !value.trim() || value.length > limit || Array.from(value).some(isControl)) throw new Error(`${name} must contain 1–${limit} printable characters.`)
  return value
}
/** Validate notation with the app's actual renderer, keeping file access, macros, HTML, and URLs out. */
export function validateMath(latex: string) {
  if (!latex.trim() || latex.length > 4000 || /\$|#|\\(?:require|href|url|html\w*|class|cssId|style|def|gdef|newcommand|renewcommand|let|includegraphics|input|include|write|openout|read)\b/.test(latex))
    throw new Error('Unsupported LaTeX. Use ordinary mathematical notation without delimiters, macros, HTML, or file commands.')
  katex.renderToString(latex, { throwOnError: true, trust: false, strict: 'error', maxExpand: 100 })
}
/** Validate a custom mode's identity and all one-argument templates before installing any of it. */
export function parseMathMode(value: unknown): MathMode {
  const mode = mathRecord(value, 'Math mode')
  const id = mathText(mode.id, 'Mode id', 80)
  if (!/^[a-z][a-z0-9-]*$/.test(id) || builtinModes.some(matchesId)) throw new Error('A custom mode needs a unique lowercase id, separate from built-in modes.')
  /** Reject collisions with a built-in subject. */
  function matchesId(item: MathMode) {
    return item.id === id
  }
  if (!Array.isArray(mode.bindings) || mode.bindings.length < 1 || mode.bindings.length > 8) throw new Error('A custom mode needs 1–8 notation templates.')
  const keys = new Set<string>()
  const bindings: MathNotation[] = []
  for (const entry of mode.bindings) {
    const binding = mathRecord(entry, 'Notation')
    const key = mathText(binding.key, 'Notation key', 1)
    const latex = mathText(binding.latex, 'Notation template', 1200)
    if (!/^[a-z]$/.test(key) || keys.has(key) || latex.split('#1').length !== 2) throw new Error('Each notation needs a unique letter key and exactly one #1 placeholder.')
    validateMath(latex.replace('#1', '{x}'))
    keys.add(key)
    bindings.push({ key, label: mathText(binding.label, 'Notation label', 80), latex })
  }
  return { id, title: mathText(mode.title, 'Mode title', 48), summary: mathText(mode.summary, 'Mode guidance', 300), bindings }
}
/** Read the configurable local model, default subject, automatic suggestions, and custom library. */
export function parseMathPreferences(value: unknown): MathPreferences {
  if (value === undefined) return defaultMathPreferences
  const record = mathRecord(value, 'math')
  for (const key of Object.keys(record)) if (!['model', 'default_mode', 'suggest_modes', 'modes'].includes(key)) throw new Error(`Unknown setting: math.${key}`)
  const model = record.model === undefined ? defaultMathPreferences.model : mathText(record.model, 'math.model', 120)
  if (!/^[a-zA-Z0-9_.:/-]+$/.test(model)) throw new Error('math.model must be an installed Ollama model name.')
  const modes: MathMode[] = []
  if (record.modes !== undefined) {
    if (!Array.isArray(record.modes) || record.modes.length > 30) throw new Error('math.modes must be an array of at most 30 custom modes.')
    for (const entry of record.modes) modes.push(parseMathMode(entry))
  }
  if (new Set(modes.map(modeId)).size !== modes.length) throw new Error('Custom mode ids must be unique.')
  const default_mode = record.default_mode === undefined ? 'general' : mathText(record.default_mode, 'math.default_mode', 80)
  if (![...builtinModes, ...modes].some(isDefault)) throw new Error('math.default_mode must name a built-in or saved custom mode.')
  const suggest_modes = record.suggest_modes === undefined ? true : record.suggest_modes
  if (typeof suggest_modes !== 'boolean') throw new Error('math.suggest_modes must be true or false.')
  /** Read the identity for duplicate detection. */
  function modeId(mode: MathMode) {
    return mode.id
  }
  /** Ensure the configured default can actually be selected. */
  function isDefault(mode: MathMode) {
    return mode.id === default_mode
  }
  return { model, default_mode, suggest_modes, modes }
}
