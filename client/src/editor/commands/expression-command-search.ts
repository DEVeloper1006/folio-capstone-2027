/**
 * Search expression templates and MathLive’s command list. Contains a replaceable asynchronous search contract, spoken shortcuts that share one symbol, and deterministic keyword ranking. Equally close matches are ordered by how often the command is typed.
 *
 * @file
 */

import { commandUsageRelevance } from './command-relevance.ts'
import { expressionCommands } from './expression-commands.ts'
import type { ExpressionCommand, ExpressionCommandGroup } from './expression-commands.ts'
import { latexLibraryCommands } from './latex-command-library.ts'
import type { LatexLibraryCommand } from './latex-command-library.ts'

/** Describe the current search text; future context can be added as explicit fields. */
export interface CommandSearchRequest {
  query: string
}

/** Return an insertable definition and its optional parent for breadcrumbs and variant navigation. */
export interface CommandMatch {
  command: ExpressionCommandGroup
  parent?: ExpressionCommandGroup
}

/** Allow another search provider without coupling menu rendering to its implementation. */
export type SearchExpressionCommands = (request: CommandSearchRequest) => Promise<readonly CommandMatch[]>

/** Make each child independently searchable while preserving catalog order for equally relevant matches. */
function flattenGroup(command: ExpressionCommandGroup): CommandMatch[] {
  /** Associate a child with its display parent without inheriting the parent's search keywords. */
  function childMatch(variant: ExpressionCommandGroup): CommandMatch {
    return { command: variant, parent: command }
  }
  return [{ command }, ...(command.variants?.map(childMatch) ?? [])]
}

const searchableCommands = expressionCommands.flatMap(flattenGroup)

/** Normalize casing, surrounding whitespace, and repeated spaces for predictable alias matching. */
function normalize(text: string) {
  return text.toLowerCase().trim().replace(/\s+/g, ' ')
}

/** Name one symbol with the words people type. `or` and `disjunction` both insert ∨; `and` and `conjunction` both insert ∧. */
const commandSearchAliases: Partial<Record<string, { label: string; keywords: readonly string[] }>> = {
  lor: { label: 'Disjunction', keywords: ['or', 'disjunction', 'disjunctions'] },
  land: { label: 'Conjunction', keywords: ['and', 'conjunction', 'conjunctions'] },
  lnot: { label: 'Negation', keywords: ['not', 'negation'] },
  infty: { label: 'Infinity', keywords: ['infinity'] },
}

/** Use the command name as the menu label, then replace it when a spoken shortcut names the same symbol. */
function withSpokenAliases(command: LatexLibraryCommand): ExpressionCommand {
  const alias = commandSearchAliases[command.id]
  if (!alias) return { ...command, label: command.id }
  return { ...command, label: alias.label, keywords: [...command.keywords, ...alias.keywords] }
}

/** Collect the names already used by a hand-written template so the library does not offer a second, plainer copy. */
function curatedCommandNames() {
  const names = new Set<string>()
  /** Record a template’s id and aliases. */
  function addCommand(command: ExpressionCommand) {
    names.add(normalize(command.id))
    for (const keyword of command.keywords) names.add(normalize(keyword))
  }
  for (const command of expressionCommands) {
    addCommand(command)
    command.variants?.forEach(addCommand)
  }
  return names
}

const curatedNames = curatedCommandNames()

/** Keep a MathLive command when the hand-written catalog does not already publish that name. */
function isAdditionalCommand(command: LatexLibraryCommand) {
  return !curatedNames.has(normalize(command.id))
}

/** Present a MathLive command as a search result that has no hand-written parent template. */
function libraryMatch(command: ExpressionCommand): CommandMatch {
  return { command }
}

const libraryCommands = latexLibraryCommands.filter(isAdditionalCommand).map(withSpokenAliases).map(libraryMatch)

/** Show the closest matches. The full command list stays searchable; the menu keeps the best rows. */
const searchResultLimit = 40

/** Rank spoken shortcuts first, then exact aliases, prefixes, and matches containing every query word. An empty search shows only the hand-written top-level templates. */
export const searchExpressionCommands: SearchExpressionCommands = async ({ query }) => {
  const text = normalize(query)
  const words = text.split(' ')
  const commands = text ? [...searchableCommands, ...libraryCommands] : searchableCommands
  /** Score each definition using its own label, ID, and aliases. */
  function rank(match: CommandMatch) {
    const terms = [match.command.id, match.command.label, ...match.command.keywords].map(normalize)
    const spokenTerms = commandSearchAliases[match.command.id]
    const spoken = spokenTerms ? [spokenTerms.label, ...spokenTerms.keywords].map(normalize) : []
    /** Match the complete query against an alias prefix. */
    function startsWithQuery(term: string) {
      return term.startsWith(text)
    }
    /** Require every query word to occur in at least one searchable term. */
    function containsWord(word: string) {
      /** Find this word inside a label or alias. */
      function contains(term: string) {
        return term.includes(word)
      }
      return terms.some(contains)
    }
    const score = !text ? (match.parent ? Infinity : 0) : spoken.includes(text) ? -1 : terms.includes(text) ? 0 : terms.some(startsWithQuery) ? 1 : words.every(containsWord) ? 2 : Infinity
    return { match, score, usage: commandUsageRelevance(match.command.id, match.command.keywords) }
  }
  /** Discard definitions that did not match the query. */
  function isMatch(result: ReturnType<typeof rank>) {
    return Number.isFinite(result.score)
  }
  /** Put a closer name match first. When two matches are equally close and the query is not empty, put the more commonly typed command first. An empty query keeps catalog order. */
  function byScore(left: ReturnType<typeof rank>, right: ReturnType<typeof rank>) {
    if (left.score !== right.score) return left.score - right.score
    if (!text) return 0
    return right.usage - left.usage
  }
  /** Expose results without the keyword provider's internal scores. */
  function toMatch(result: ReturnType<typeof rank>) {
    return result.match
  }
  return commands.map(rank).filter(isMatch).sort(byScore).map(toMatch).slice(0, searchResultLimit)
}
