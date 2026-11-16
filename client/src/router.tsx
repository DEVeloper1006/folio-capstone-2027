/**
 * Configure the application’s TanStack router. Contains router construction and route-type registration using the generated route tree.
 *
 * @file
 */

import { createRouter as createTanStackRouter } from '@tanstack/react-router'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { seedNotebook } from './notebook/use-page-state'
import { routeTree } from './routeTree.gen'

/** Create the application router with the generated routes, scroll restoration, and intent-based preloading. */
export function getRouter() {
  const client = new QueryClient({ defaultOptions: { queries: { staleTime: Infinity, gcTime: Infinity } } })
  seedNotebook(client)
  /** Provide the same cache to routes and mounted math fields for this router. */
  function QueryProvider({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={client}>{children}</QueryClientProvider>
  }
  const router = createTanStackRouter({
    routeTree,
    Wrap: QueryProvider,
    scrollRestoration: true,
    defaultPreload: 'intent',
    defaultPreloadStaleTime: 0,
  })

  return router
}

declare module '@tanstack/react-router' {
  interface Register {
    router: ReturnType<typeof getRouter>
  }
}
