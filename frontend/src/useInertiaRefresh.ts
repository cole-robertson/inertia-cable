import { useCallback, useEffect, useRef, useState } from 'react'
import { createInertiaRefresh, type RefreshOptions, type RefreshState } from './createInertiaRefresh'

export interface UseInertiaRefreshOptions extends RefreshOptions {
  scope: string
  enabled?: boolean
}
const initialState: RefreshState = { refreshing: false, lastRefreshedAt: null, error: null }

/** Own one coordinator per mounted page scope; share refresh across its subscriptions. */
export function useInertiaRefresh({ scope, only, enabled = true, debounce, pollInterval }: UseInertiaRefreshOptions) {
  const coordinator = useRef<ReturnType<typeof createInertiaRefresh> | null>(null)
  const [state, setState] = useState(initialState)
  const keys = JSON.stringify(only)
  useEffect(() => {
    setState(initialState)
    if (!enabled) return
    const instance = createInertiaRefresh({ only: JSON.parse(keys), debounce, pollInterval })
    coordinator.current = instance
    const unsubscribe = instance.subscribe(() => setState(instance.getSnapshot()))
    return () => {
      coordinator.current = null
      unsubscribe()
      instance.dispose()
    }
  }, [scope, keys, enabled, debounce, pollInterval])
  const refresh = useCallback((keys?: string[]) => coordinator.current?.refresh(keys), [])
  const visit = useCallback((run: () => void) => {
    if (coordinator.current) coordinator.current.visit(run)
    else run()
  }, [])
  return { refresh, visit, ...state }
}

