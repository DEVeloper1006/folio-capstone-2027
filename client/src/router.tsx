/**
 * Configure the application’s TanStack router. Contains router construction and route-type registration using the generated route tree.
 *
 * @file
 */

import { createRouter as createTanStackRouter } from '@tanstack/react-router'
import { routeTree } from './routeTree.gen'

/** Create the application router with the generated routes, scroll restoration, and intent-based preloading. */
export function getRouter() {
  const router = createTanStackRouter({
    routeTree,
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
