/**
 * Configure frontend code-quality and documentation checks. Contains the TanStack ESLint defaults, project overrides, JSDoc requirements, and generated-file exclusions.
 *
 * @file
 */

//  @ts-check

import jsdoc from 'eslint-plugin-jsdoc'

import { tanstackConfig } from '@tanstack/eslint-config'

/** Require documentation blocks to occupy their own lines beside declarations. */
const standaloneDocumentation = {
  meta: {
    type: 'layout',
    schema: [],
    messages: {
      standalone: 'Put documentation above a named declaration on separate lines; do not insert it inside an expression.',
    },
  },
  /** Inspect comment boundaries without changing code or moving declarations. */
  create(context) {
    return {
      /** Reject JSDoc blocks sharing a line with surrounding executable code. */
      Program() {
        const source = context.sourceCode
        for (const comment of source.getAllComments()) {
          if (comment.type !== 'Block' || !comment.value.startsWith('*')) continue
          const before = source.getTokenBefore(comment)
          const after = source.getTokenAfter(comment)
          if (before?.loc.end.line === comment.loc.start.line || after?.loc.start.line === comment.loc.end.line) {
            context.report({ loc: comment.loc, messageId: 'standalone' })
          }
        }
      },
    }
  },
}

export default [
  ...tanstackConfig,
  {
    rules: {
      'import/no-cycle': 'off',
      'import/order': 'off',
      'sort-imports': 'off',
      '@typescript-eslint/array-type': 'off',
      '@typescript-eslint/require-await': 'off',
      'pnpm/json-enforce-catalog': 'off',
    },
  },
  {
    files: ['**/*.{ts,tsx,js}'],
    plugins: {
      jsdoc,
      folio: { rules: { 'standalone-documentation': standaloneDocumentation } },
    },
    settings: { jsdoc: { mode: 'typescript' } },
    rules: {
      'folio/standalone-documentation': 'error',
      'jsdoc/require-file-overview': 'error',
      'jsdoc/require-jsdoc': [
        'error',
        {
          enableFixer: false,
          checkAllFunctionExpressions: true,
          require: {
            FunctionDeclaration: true,
            ArrowFunctionExpression: true,
            FunctionExpression: true,
            MethodDefinition: true,
          },
          contexts: ['ArrowFunctionExpression', 'FunctionExpression'],
        },
      ],
      'jsdoc/require-description': 'error',
    },
  },
  {
    ignores: ['eslint.config.js', 'prettier.config.js', 'src/routeTree.gen.ts', '.output/**', '.mac/**'],
  },
]
