import { useEffect, useRef, useCallback, useState } from 'react'
import { router } from '@inertiajs/react'
import { getConsumer } from './consumer'
import { useInertiaCableConsumer } from './InertiaCableProvider'

export interface RefreshPayload {
  type: 'refresh'
  model: string
  id: number | null
  action: string
  timestamp: string
  extra?: Record<string, unknown>
}

export interface MessagePayload {
  type: 'message'
  data: Record<string, unknown>
}

export type CablePayload = RefreshPayload | MessagePayload

export interface UseInertiaCableOptions {
  only?: string[]
  except?: string[]
  onRefresh?: (data: RefreshPayload) => void
  onMessage?: (data: Record<string, unknown>) => void
  onConnected?: () => void
  onDisconnected?: () => void
  debounce?: number
  enabled?: boolean
  /** Replace the default reload. Share one coordinator here across subscriptions. */
  refresh?: (context: RefreshContext) => void | Promise<void>
  onRejected?: () => void
}

export interface RefreshContext {
  reason: 'broadcast' | 'reconnect'
  only?: string[]
  except?: string[]
}
export type ConnectionStatus = 'disabled' | 'connecting' | 'connected' | 'reconnecting' | 'rejected'

export interface UseInertiaCableReturn {
  connected: boolean
  status: ConnectionStatus
  refreshing: boolean
  lastRefreshedAt: number | null
  refreshError: string | null
}

export function useInertiaCable(
  signedStreamName: string | null | undefined,
  options: UseInertiaCableOptions = {}
): UseInertiaCableReturn {
  const { debounce = 100, enabled = true } = options
  const optionsRef = useRef(options)
  optionsRef.current = { ...options, debounce }

  const [connected, setConnected] = useState(false)
  const [status, setStatus] = useState<ConnectionStatus>('disabled')
  const [refreshing, setRefreshing] = useState(false)
  const [lastRefreshedAt, setLastRefreshedAt] = useState<number | null>(null)
  const [refreshError, setRefreshError] = useState<string | null>(null)
  const generationRef = useRef(0)
  const pendingRefreshes = useRef(0)
  const refreshSequence = useRef(0)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const hasConnectedRef = useRef(false)

  const contextConsumer = useInertiaCableConsumer()

  const reloadProps = useCallback((reason: RefreshContext['reason']) => {
    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      const opts = optionsRef.current
      const generation = generationRef.current
      const sequence = ++refreshSequence.current
      const current = () => generation === generationRef.current
      const latest = () => current() && sequence === refreshSequence.current
      const success = () => { if (latest()) { setLastRefreshedAt(Date.now()); setRefreshError(null) } }
      const failure = () => { if (latest()) setRefreshError('Refresh failed. Retrying on the next update.') }
      let started = false
      const start = () => {
        if (!current() || started) return
        started = true
        pendingRefreshes.current += 1
        setRefreshing(true)
      }
      const finish = () => {
        if (!current() || !started) return
        started = false
        pendingRefreshes.current -= 1
        setRefreshing(pendingRefreshes.current > 0)
      }
      if (opts.refresh) {
        try {
          const result = opts.refresh({ reason, only: opts.only, except: opts.except })
          // A void callback delegates lifecycle/freshness to its coordinator.
          if (result) {
            start()
            void Promise.resolve(result).then(success, failure).finally(finish)
          }
        } catch { failure() }
        return
      }
      router.reload({
        preserveErrors: true,
        ...(opts.only ? { only: opts.only } : {}),
        ...(opts.except ? { except: opts.except } : {}),
        onStart: start,
        onSuccess: success,
        onError: success,
        onNetworkError: failure,
        onFinish: finish,
      })
    }, optionsRef.current.debounce)
  }, [])

  const handleRefresh = useCallback((data: RefreshPayload) => {
    optionsRef.current.onRefresh?.(data)
    reloadProps('broadcast')
  }, [reloadProps])

  useEffect(() => {
    setConnected(false)
    setStatus(!signedStreamName || !enabled ? 'disabled' : 'connecting')
    setLastRefreshedAt(null)
    setRefreshError(null)
    setRefreshing(false)
    pendingRefreshes.current = 0
    if (!signedStreamName || !enabled) return
    let alive = true

    const consumer = contextConsumer ?? getConsumer()
    hasConnectedRef.current = false
    setConnected(false)

    const subscription = consumer.subscriptions.create(
      { channel: 'InertiaCable::StreamChannel', signed_stream_name: signedStreamName },
      {
        connected() {
          if (!alive) return
          setConnected(true)
          setStatus('connected')
          optionsRef.current.onConnected?.()

          // Catch up on missed changes after a reconnection
          if (hasConnectedRef.current) {
            reloadProps('reconnect')
          }
          hasConnectedRef.current = true
        },

        disconnected() {
          if (!alive) return
          setConnected(false)
          setStatus(hasConnectedRef.current ? 'reconnecting' : 'connecting')
          optionsRef.current.onDisconnected?.()
        },

        rejected() {
          if (!alive) return
          setConnected(false)
          setStatus('rejected')
          optionsRef.current.onRejected?.()
        },

        received(data: CablePayload) {
          if (!alive) return
          if (data.type === 'refresh') {
            handleRefresh(data)
          } else if (data.type === 'message') {
            optionsRef.current.onMessage?.(data.data)
          }
        },
      }
    )

    return () => {
      alive = false
      generationRef.current += 1
      if (timerRef.current) clearTimeout(timerRef.current)
      subscription.unsubscribe()
    }
  }, [signedStreamName, enabled, handleRefresh, reloadProps, contextConsumer])

  return { connected, status, refreshing, lastRefreshedAt, refreshError }
}
