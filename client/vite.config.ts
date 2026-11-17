/**
 * Configure the frontend development and production build. Contains the TanStack Start, React, and Nitro Vite plugin setup.
 *
 * @file
 */

import { defineConfig, loadEnv } from 'vite'

import { tanstackStart } from '@tanstack/react-start/plugin/vite'

import viteReact from '@vitejs/plugin-react'
import { nitro } from 'nitro/vite'

const config = defineConfig({
  resolve: { tsconfigPaths: true },
  plugins: [
    {
      name: 'folio-local-completions',
      enforce: 'pre',
      /** Forward same-origin local completion requests without exposing the API key. */
      configureServer(server) {
        const key = process.env.OPENROUTER_API_KEY ?? loadEnv(server.config.mode, server.config.envDir, 'OPENROUTER_').OPENROUTER_API_KEY
        server.middlewares.use('/folio-local/v1/chat/completions', async (req, res) => {
          if (req.method !== 'POST' || req.headers.origin !== 'http://' + req.headers.host || !['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress ?? '')) {
            res.writeHead(403).end()
            return
          }
          if (!key) {
            res.writeHead(503).end()
            return
          }
          try {
            let body = ''
            for await (const chunk of req) {
              body += chunk
              if (body.length > 64000) {
                res.writeHead(413).end()
                return
              }
            }
            const reply = await fetch('https://openrouter.ai/api/v1/chat/completions', {
              method: 'POST',
              headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
              body,
            })
            res.writeHead(reply.status, { 'Content-Type': 'application/json' }).end(await reply.text())
          } catch {
            res.writeHead(502).end()
          }
        })
      },
    },
    nitro({ rollupConfig: { external: [/^@sentry\//] } }),
    tanstackStart({ spa: { enabled: process.env.FOLIO_DESKTOP === '1' } }),
    viteReact(),
  ],
})

export default config
