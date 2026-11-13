/**
 * Configure the frontend development and production build. Contains the TanStack Start, React, and Nitro Vite plugin setup.
 *
 * @file
 */

import { defineConfig } from 'vite'

import { tanstackStart } from '@tanstack/react-start/plugin/vite'

import viteReact from '@vitejs/plugin-react'
import { nitro } from 'nitro/vite'

const config = defineConfig({
  resolve: { tsconfigPaths: true },
  plugins: [nitro({ rollupConfig: { external: [/^@sentry\//] } }), tanstackStart(), viteReact()],
})

export default config
