import { useEffect, useRef, useCallback } from 'react'
import { router } from '@inertiajs/react'
import { getConsumer } from './consumer'

export interface RefreshPayload {
  type: 'refresh'
  model: string
  id: number | null
  action: string
  timestamp: string
}

export interface UseInertiaCableOptions {
  only?: string[]
  except?: string[]
  onRefresh?: (data: RefreshPayload) => void
  debounce?: number
  enabled?: boolean
}

export function useInertiaCable(
  signedStreamName: string | null | undefined,
  options: UseInertiaCableOptions = {}
) {
  const { only, except, onRefresh, debounce = 100, enabled = true } = options
  const optionsRef = useRef({ only, except, onRefresh, debounce })
  optionsRef.current = { only, except, onRefresh, debounce }

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const handleRefresh = useCallback((data: RefreshPayload) => {
    const opts = optionsRef.current
    opts.onRefresh?.(data)

    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      router.reload({
        only: opts.only,
        except: opts.except,
      })
    }, opts.debounce)
  }, [])

  useEffect(() => {
    if (!signedStreamName || !enabled) return

    const consumer = getConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: 'InertiaCable::StreamChannel', signed_stream_name: signedStreamName },
      {
        received(data: RefreshPayload) {
          if (data.type === 'refresh') {
            handleRefresh(data)
          }
        },
      }
    )

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      subscription.unsubscribe()
    }
  }, [signedStreamName, enabled, handleRefresh])
}
