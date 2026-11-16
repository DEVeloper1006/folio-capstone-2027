/**
 * Search expression templates and symbols. Contains a replaceable asynchronous search contract and deterministic keyword ranking. Equally close matches are ordered by how often the command is typed.
 *
 * @file
 */

import { expressionCommands, expressionSymbolCommands } from './expression-commands.ts'
import type { ExpressionCommand } from './expression-commands.ts'

/** Describe the current search text; future context can be added as explicit fields. */
export interface CommandSearchRequest {
  query: string
}

/** Return an insertable definition and its optional parent for breadcrumbs and variant navigation. */
export interface CommandMatch {
  command: ExpressionCommand
  parent?: ExpressionCommand
}

/** Allow another search provider without coupling menu rendering to its implementation. */
export type SearchExpressionCommands = (request: CommandSearchRequest) => Promise<readonly CommandMatch[]>

/** Include a command and every nested variant. A variant remembers its immediate parent and does not inherit that parent's keywords. */
function flattenCommand(command: ExpressionCommand, parent?: ExpressionCommand): CommandMatch[] {
  /** Search one nested variant under this command. */
  function flattenVariant(variant: ExpressionCommand) {
    return flattenCommand(variant, command)
  }
  const nested = command.variants?.flatMap(flattenVariant) ?? []
  return [parent ? { command, parent } : { command }, ...nested]
}

/** List the hand-written templates and their variants. An empty search uses only this list. */
function flattenTemplate(command: ExpressionCommand) {
  return flattenCommand(command)
}

const templateMatches = expressionCommands.flatMap(flattenTemplate)
const symbolMatches = expressionSymbolCommands.flatMap(flattenTemplate)

/** Normalize casing, surrounding whitespace, and repeated spaces for predictable alias matching. */
function normalize(text: string) {
  return text.toLowerCase().trim().replace(/\s+/g, ' ')
}

/** Show the closest matches. The full command list stays searchable; the menu keeps the best rows. */
const searchResultLimit = 40

/** Rank exact names ahead of prefixes and prefixes ahead of looser matches. An empty search shows only the hand-written top-level templates. */
export const searchExpressionCommands: SearchExpressionCommands = async ({ query }) => {
  const text = normalize(query)
  const words = text.split(' ')
  const commands = text ? [...templateMatches, ...symbolMatches] : templateMatches
  /** Score each definition using its own label, id, and aliases. */
  function rank(match: CommandMatch) {
    const terms = [match.command.id, match.command.label, ...match.command.keywords].map(normalize)
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
    const score = !text ? (match.parent ? Infinity : 0) : terms.includes(text) ? 0 : terms.some(startsWithQuery) ? 1 : words.every(containsWord) ? 2 : Infinity
    return { match, score, usage: match.command.relevance }
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
