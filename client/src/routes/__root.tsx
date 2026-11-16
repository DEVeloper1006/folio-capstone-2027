/**
 * Define the shared HTML document for the notebook. Contains page metadata, the stored-theme boot script, MathLive fonts, Markdown mathematics styles, theme tokens, application styles, shared control styles, and the root document component.
 *
 * @file
 */

import { HeadContent, Scripts, createRootRoute } from '@tanstack/react-router'
import type { ReactNode } from 'react'

import appStylesheetUrl from '../styles.css?url'
import componentLibraryStylesheetUrl from '../component-library/component-library.css?url'
import themeStylesheetUrl from '../theme/theme.css?url'
import { themeBootScript } from '#/theme/theme-boot.ts'
import mathFontsStylesheetUrl from 'mathlive/fonts.css?url'
import markdownMathStylesheetUrl from 'katex/dist/katex.min.css?url'

export const Route = createRootRoute({
  /** Supply document metadata and stylesheets for mathematical editors, rendered Markdown mathematics, the notebook layout, and shared controls. */
  head: () => ({
    meta: [
      {
        charSet: 'utf-8',
      },
      {
        name: 'viewport',
        content: 'width=device-width, initial-scale=1',
      },
      {
        title: 'Folio',
      },
    ],
    links: [
      {
        rel: 'stylesheet',
        href: themeStylesheetUrl,
      },
      {
        rel: 'stylesheet',
        href: mathFontsStylesheetUrl,
      },
      {
        rel: 'stylesheet',
        href: markdownMathStylesheetUrl,
      },
      {
        rel: 'stylesheet',
        href: appStylesheetUrl,
      },
      {
        rel: 'stylesheet',
        href: componentLibraryStylesheetUrl,
      },
    ],
  }),
  shellComponent: RootDocument,
})

/** Render the shared HTML document around every route and include TanStack’s head and client scripts. */
function RootDocument({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeBootScript }} />
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  )
}
