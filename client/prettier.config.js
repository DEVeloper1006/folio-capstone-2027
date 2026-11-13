/**
 * Define the repository’s source formatting style. Contains Prettier settings for quotes, semicolons, indentation, line endings, and trailing commas.
 *
 * @file
 */

//  @ts-check

/** @type {import('prettier').Config & import('prettier-plugin-jsdoc').Options} */
const config = {
  plugins: ['prettier-plugin-jsdoc'],
  printWidth: 300,
  jsdocPrintWidth: 300,
  tabWidth: 2,
  useTabs: false,
  endOfLine: 'lf',
  semi: false,
  singleQuote: true,
  trailingComma: 'all',
}

export default config
