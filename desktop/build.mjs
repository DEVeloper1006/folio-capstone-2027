/**
 * Build the shared frontend as an offline SPA and copy its public assets beside Electron.
 *
 * @file
 */
import { spawnSync } from 'node:child_process'
import { cpSync, rmSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const client = fileURLToPath(new URL('../client', import.meta.url))
const renderer = fileURLToPath(new URL('./renderer', import.meta.url))
const result = spawnSync(process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm', ['build'], { cwd: client, env: { ...process.env, FOLIO_DESKTOP: '1' }, stdio: 'inherit' })
if (result.status !== 0) process.exit(result.status ?? 1)
rmSync(renderer, { recursive: true, force: true })
cpSync(client + '/.output/public', renderer, { recursive: true })
