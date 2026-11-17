/**
 * Package the built renderer and Electron entry points for the current operating system.
 *
 * @file
 */
import { packager } from '@electron/packager'
import { fileURLToPath } from 'node:url'

const output = await packager({
  dir: fileURLToPath(new URL('.', import.meta.url)),
  name: 'Folio',
  executableName: 'Folio',
  appBundleId: 'app.folio.notebook',
  out: fileURLToPath(new URL('./release', import.meta.url)),
  overwrite: true,
  electronZipDir: process.env.ELECTRON_ZIP_DIR,
  asar: true,
  ignore: [/^\/release/, /^\/node_modules/, /^\/package-lock\.json$/, /^\/.*\.mjs$/],
})
console.log(output.join('\n'))
