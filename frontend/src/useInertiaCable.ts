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
}

export interface UseInertiaCableReturn {
  connected: boolean
}

export function useInertiaCable(
  signedStreamName: string | null | undefined,
  options: UseInertiaCableOptions = {}
): UseInertiaCableReturn {
  const { only, except, onRefresh, onMessage, onConnected, onDisconnected, debounce = 100, enabled = true } = options
  const optionsRef = useRef({ only, except, onRefresh, onMessage, onConnected, onDisconnected, debounce })
  optionsRef.current = { only, except, onRefresh, onMessage, onConnected, onDisconnected, debounce }

  const [connected, setConnected] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const hasConnectedRef = useRef(false)

  const contextConsumer = useInertiaCableConsumer()

  const reloadProps = useCallback(() => {
    const opts = optionsRef.current
    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      router.reload({
        ...(opts.only ? { only: opts.only } : {}),
        ...(opts.except ? { except: opts.except } : {}),
      })
    }, opts.debounce)
  }, [])

  const handleRefresh = useCallback((data: RefreshPayload) => {
    optionsRef.current.onRefresh?.(data)
    reloadProps()
  }, [reloadProps])

  useEffect(() => {
    if (!signedStreamName || !enabled) return

    const consumer = contextConsumer ?? getConsumer()
    hasConnectedRef.current = false
    setConnected(false)

    const subscription = consumer.subscriptions.create(
      { channel: 'InertiaCable::StreamChannel', signed_stream_name: signedStreamName },
      {
        connected() {
          setConnected(true)
          optionsRef.current.onConnected?.()

          // Catch up on missed changes after a reconnection
          if (hasConnectedRef.current) {
            reloadProps()
          }
          hasConnectedRef.current = true
        },

        disconnected() {
          setConnected(false)
          optionsRef.current.onDisconnected?.()
        },

        rejected() {
          setConnected(false)
        },

        received(data: CablePayload) {
          if (data.type === 'refresh') {
            handleRefresh(data)
          } else if (data.type === 'message') {
            optionsRef.current.onMessage?.(data.data)
          }
        },
      }
    )

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      subscription.unsubscribe()
    }
  }, [signedStreamName, enabled, handleRefresh, reloadProps, contextConsumer])

  return { connected }
}
