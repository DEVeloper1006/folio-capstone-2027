import { createFileRoute } from '@tanstack/react-router'

import { useCounterStore } from '#/state/counter-store-provider.tsx'

export const Route = createFileRoute('/')({ component: Home })

function Home() {
  return (
    <main>
      <h1>Folio</h1>
      <section className="counter" aria-labelledby="counter-label">
        <h2 id="counter-label">Counter</h2>
        <Count />
        <IncrementButton />
      </section>
    </main>
  )
}

function Count() {
  const count = useCounterStore((state) => state.count)

  return <p className="count">{count}</p>
}

function IncrementButton() {
  const increment = useCounterStore((state) => state.increment)

  return (
    <button type="button" onClick={increment}>
      Increment
    </button>
  )
}
