# Folio

Minimal TanStack Start application in `client/`. The home page is server-rendered, and the counter uses a Zustand store created for each application instance.

## Installation

```bash
cd client
pnpm install
```

Requires Node.js and pnpm. Run the commands below from `client/`.

## Development

```bash
pnpm dev
```

The dev server runs at http://localhost:3000 with the standard Vite and TanStack Start setup, including SSR.

## Checks

```bash
pnpm typecheck
pnpm lint
pnpm format:check
pnpm format
```

## Production

```bash
pnpm build
pnpm start
```

`pnpm build` uses TanStack Start’s standard Vite production build. `pnpm start` serves the generated Node server at `client/.output/server/index.mjs`.
