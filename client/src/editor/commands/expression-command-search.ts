/**
 * Search local expression definitions independently of the menu. Contains a replaceable asynchronous search contract and deterministic keyword ranking for parents and variants.
 *
 * @file
 */

import { expressionCommands } from './expression-commands.ts'
import type { ExpressionCommandGroup } from './expression-commands.ts'

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

/** Rank exact aliases first, then prefixes and matches containing every query word. Empty searches show only top-level definitions. */
export const searchExpressionCommands: SearchExpressionCommands = async ({ query }) => {
  const text = normalize(query)
  const words = text.split(' ')
  /** Score each definition using its own label, ID, and aliases. */
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
    return { match, score }
  }
  /** Discard definitions that did not match the query. */
  function isMatch(result: ReturnType<typeof rank>) {
    return Number.isFinite(result.score)
  }
  /** Preserve catalog order when two definitions have equal relevance. */
  function byScore(left: ReturnType<typeof rank>, right: ReturnType<typeof rank>) {
    return left.score - right.score
  }
  /** Expose results without the keyword provider's internal scores. */
  function toMatch(result: ReturnType<typeof rank>) {
    return result.match
  }
  return searchableCommands.map(rank).filter(isMatch).sort(byScore).map(toMatch)
}
