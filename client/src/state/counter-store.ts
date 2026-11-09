import { createStore } from 'zustand'

export type CounterState = {
  count: number
  increment: () => void
}

export function createCounterStore() {
  return createStore<CounterState>()((set) => ({
    count: 0,
    increment: () => {
      set((state) => ({ count: state.count + 1 }))
    },
  }))
}
