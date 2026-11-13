/**
 * Define the shared HTML document for the notebook. Contains page metadata, MathLive font and application stylesheet links, and the root document component.
 *
 * @file
 */

import { HeadContent, Scripts, createRootRoute } from '@tanstack/react-router'
import type { ReactNode } from 'react'

import appStylesheetUrl from '../styles.css?url'
import mathFontsStylesheetUrl from 'mathlive/fonts.css?url'

export const Route = createRootRoute({
  /** Supply the document metadata and stylesheets required to display the notebook and MathLive fonts. */
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
        href: mathFontsStylesheetUrl,
      },
      {
        rel: 'stylesheet',
        href: appStylesheetUrl,
      },
    ],
  }),
  shellComponent: RootDocument,
})

/** Render the shared HTML document around every route and include TanStack’s head and client scripts. */
function RootDocument({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  )
}
