/**
 * Describe the strict browser distribution using Plotly's public API declarations.
 *
 * @file
 */
declare module 'plotly.js-strict-dist-min' {
  import type * as Plotly from 'plotly.js'

  const plotly: typeof Plotly
  export default plotly
}
