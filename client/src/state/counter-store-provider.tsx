import { createContext, useContext, useState } from 'react'
import type { ReactNode } from 'react'
import { useStore } from 'zustand'

import { createCounterStore } from '#/state/counter-store.ts'
import type { CounterState } from '#/state/counter-store.ts'

export type CounterStore = ReturnType<typeof createCounterStore>

const CounterStoreContext = createContext<CounterStore | null>(null)

export function CounterStoreProvider({ children }: { children: ReactNode }) {
  // A new store for each application tree, so server requests do not share it.
  const [store] = useState(createCounterStore)

  return (
    <CounterStoreContext.Provider value={store}>
      {children}
    </CounterStoreContext.Provider>
  )
}

export function useCounterStore<T>(selector: (state: CounterState) => T): T {
  const store = useContext(CounterStoreContext)

  if (store === null) {
    throw new Error('useCounterStore must be used within CounterStoreProvider')
  }

  return useStore(store, selector)
}
