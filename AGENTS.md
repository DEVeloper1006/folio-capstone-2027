# Folio repository rules

This file defines the conventions for changes to Folio. Apply them to new code and maintain them when editing existing code.

## Documentation

- Maintain `CONTRIBUTING.md` when the stack, setup commands, code patterns, tools, or naming conventions change. Keep it concise and link here for detailed rules.
- Put a purpose comment at the very top of every handwritten source file, before imports, directives, or other comments. Explain what the file does and what it contains. Use a JSDoc block with an `@file` tag for JavaScript and TypeScript, a block comment for CSS, and `#` comments for YAML and other line-comment formats.
- Document every function, including local helpers, React components, callbacks, and navigation rule resolvers. Place its JSDoc immediately before the declaration or callback. Do not leave empty comment blocks.
- Use the `explain-engineering` skill when available. Write for an engineer who has not read the implementation: describe concrete inputs, actions, outputs, and meaningful side effects. State behavior first and explain its purpose when that is not obvious.
- Use specific language: “Restore the previous selection from the current growth sequence” rather than “Handle selection logic.” Explain fallback behavior, mutation, cleanup, and limitations when they affect callers.
- Do not repeat TypeScript types in prose or add redundant `@param` and `@returns` tags. Describe what values mean and what the function guarantees instead.
- Put documentation blocks on their own lines above named declarations. Never place a docstring inside a call, JSX expression, or between `return` and its value. Extract documented callbacks into named functions or constants before passing them to APIs. Only short trailing comments may share a line with code, after the code. Return a named cleanup function rather than placing a multiline comment between `return` and an anonymous function.
- Update the file overview and affected function comments in the same change as their behavior. Review comments for accuracy; lint can require their presence but cannot verify their meaning.
- Do not hand-edit generated files, lockfiles, dependencies, build output, or binary documents to add comments. Strict JSON does not support comments; describe those configuration files in nearby documentation. Markdown and Cursor rule frontmatter keep their required document structure.

## Formatting and code quality

- Follow `FRONTEND_NAMING.md` for frontend names and update it when naming patterns change.
- Use the repository's local Prettier version for formatting. Use `prettier-plugin-jsdoc` to wrap documentation comments and ESLint for code-quality and JSDoc checks. Keep one formatter responsible for each language.
- Format on save in Cursor. Use a 300-character wrap width for code and JSDoc, two spaces, LF line endings, single quotes in JavaScript/TypeScript, no semicolons, and trailing commas as configured in `client/prettier.config.js`.
- Keep TypeScript strict. Prefer named functions and exports, explicit domain names, and small functions with one clear responsibility. Do not add `any`, suppression comments, or abstractions merely to silence a check.
- Keep all custom movement and selection rules in `client/src/editor/navigation/navigation-rules.ts`. Keyboard decoding, structure extraction, and MathLive event handling stay in their own files under `client/src/editor/`. Import the editor from `client/src/editor/index.ts`.
- Use current official documentation when changing version-sensitive package APIs or editor configuration.

## Scope and verification

- Preserve unrelated work and the source documents in `.mac/`.
- Do not add tests or extend existing tests until Saad asks to resume test development. Documentation-only edits may update existing test comments without changing assertions or fixtures.
- For current work, validate with the relevant formatting, lint, TypeScript, build, or manual browser checks. Do not add a test framework.
- Do not commit, push, publish, or deploy unless asked.

## Examples

```ts
/**
 * Translate keyboard combinations into named navigation actions. Contains the keyboard decoder and action and selection types.
 *
 * @file
 */

/** Restore the previous selection from the current growth sequence. Keep the current selection when that sequence has no earlier entry. */
function shrinkSelection() {
  // Implementation follows the documented behavior.
}
```
