/**
 * Hydrate browser pages and mount the offline desktop SPA without server markup assumptions.
 *
 * @file
 */
import { StrictMode, startTransition } from 'react'
import { createRoot, hydrateRoot } from 'react-dom/client'
import { StartClient } from '@tanstack/react-start/client'

/** Start the shared router using the rendering mode of the current host. */
function boot() {
  const application = (
    <StrictMode>
      <StartClient />
    </StrictMode>
  )
  if (window.folioDesktop) createRoot(document).render(application)
  else hydrateRoot(document, application)
}
startTransition(boot)
