import { act, cleanup, configure, renderHook } from '@testing-library/react'
import { router } from '@inertiajs/react'
import type { Consumer } from '@rails/actioncable'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { setConsumer } from '../src/consumer'
import { useInertiaCable, type CablePayload } from '../src/useInertiaCable'

interface Callbacks {
  rejected(): void
  connected(): void
  disconnected(): void
  received(data: CablePayload): void
}

const refresh: CablePayload = {
  type: 'refresh', model: 'Message', id: 1, action: 'create', timestamp: '',
}

describe('useInertiaCable', () => {
  let callbacks: Callbacks
  let unsubscribe: ReturnType<typeof vi.fn>
  let subscribe: ReturnType<typeof vi.fn>

  beforeEach(() => {
    vi.useFakeTimers()
    vi.spyOn(router, 'reload').mockImplementation(() => {})
    unsubscribe = vi.fn()
    subscribe = vi.fn((_identifier, handlers: Callbacks) => {
      callbacks = handlers
      return { unsubscribe }
    })
    setConsumer({ subscriptions: { create: subscribe } } as unknown as Consumer)
  })

  afterEach(() => {
    cleanup()
    configure({ reactStrictMode: false })
    vi.useRealTimers()
  })

  it('coalesces refreshes into a partial reload that preserves validation errors', () => {
    renderHook(() => useInertiaCable('signed', { only: ['messages'] }))
    act(() => {
      callbacks.received(refresh)
      vi.advanceTimersByTime(50)
      callbacks.received(refresh)
      vi.advanceTimersByTime(99)
    })
    expect(router.reload).not.toHaveBeenCalled()
    act(() => vi.advanceTimersByTime(1))
    expect(router.reload).toHaveBeenCalledOnce()
    expect(router.reload).toHaveBeenCalledWith(expect.objectContaining({
      only: ['messages'], preserveErrors: true,
    }))
  })

  it('passes except and safely omits undefined prop filters', () => {
    renderHook(() => useInertiaCable('signed', { only: undefined, except: ['metadata'] }))
    act(() => {
      callbacks.received(refresh)
      vi.runAllTimers()
    })
    expect(router.reload).toHaveBeenCalledWith(expect.objectContaining({ except: ['metadata'], preserveErrors: true }))
  })

  it('reloads on reconnection but not the initial connection', () => {
    const { result } = renderHook(() => useInertiaCable('signed'))
    act(() => callbacks.connected())
    expect(result.current.connected).toBe(true)
    expect(router.reload).not.toHaveBeenCalled()
    act(() => callbacks.disconnected())
    expect(result.current.connected).toBe(false)
    act(() => {
      callbacks.connected()
      vi.runAllTimers()
    })
    expect(router.reload).toHaveBeenCalledOnce()
    expect(router.reload).toHaveBeenCalledWith(expect.objectContaining({ preserveErrors: true }))
  })

  it('delivers every direct message without scheduling a reload', () => {
    const onMessage = vi.fn()
    renderHook(() => useInertiaCable('signed', { onMessage }))
    act(() => {
      callbacks.received({ type: 'message', data: { progress: 1 } })
      callbacks.received({ type: 'message', data: { progress: 2 } })
      vi.runAllTimers()
    })
    expect(onMessage.mock.calls).toEqual([[{ progress: 1 }], [{ progress: 2 }]])
    expect(router.reload).not.toHaveBeenCalled()
  })

  it('delegates broadcast and reconnect invalidations without also reloading', () => {
    const customRefresh = vi.fn()
    const { result } = renderHook(() => useInertiaCable('signed', { refresh: customRefresh, only: ['messages'] }))
    act(() => { callbacks.connected(); callbacks.received(refresh); vi.runAllTimers() })
    expect(customRefresh).toHaveBeenLastCalledWith(expect.objectContaining({ reason: 'broadcast', only: ['messages'] }))
    act(() => callbacks.disconnected())
    expect(result.current.status).toBe('reconnecting')
    act(() => { callbacks.connected(); vi.runAllTimers() })
    expect(customRefresh).toHaveBeenLastCalledWith(expect.objectContaining({ reason: 'reconnect' }))
    expect(router.reload).not.toHaveBeenCalled()
    expect(result.current.lastRefreshedAt).toBeNull()
  })

  it('reports rejection and resets status when disabled', () => {
    const onRejected = vi.fn()
    const { result, rerender } = renderHook(({ enabled }) => useInertiaCable('signed', { enabled, onRejected }), { initialProps: { enabled: true } })
    act(() => callbacks.rejected())
    expect(result.current.status).toBe('rejected')
    expect(onRejected).toHaveBeenCalledOnce()
    rerender({ enabled: false })
    expect(result.current.status).toBe('disabled')
  })

  it('reports an asynchronous refresh failure without claiming fresh data', async () => {
    const { result } = renderHook(() => useInertiaCable('signed', { refresh: async () => { throw new Error('Offline') } }))
    await act(async () => { callbacks.received(refresh); vi.runAllTimers() })
    expect(result.current.refreshing).toBe(false)
    expect(result.current.lastRefreshedAt).toBeNull()
    expect(result.current.refreshError).toContain('Refresh failed')
  })

  it('tracks completion of an asynchronous custom refresh', async () => {
    let finish!: () => void
    const customRefresh = () => new Promise<void>((resolve) => { finish = resolve })
    const { result } = renderHook(() => useInertiaCable('signed', { refresh: customRefresh }))
    act(() => { callbacks.received(refresh); vi.runAllTimers() })
    expect(result.current.refreshing).toBe(true)
    expect(result.current.lastRefreshedAt).toBeNull()
    await act(async () => finish())
    expect(result.current.refreshing).toBe(false)
    expect(result.current.lastRefreshedAt).not.toBeNull()
  })

  it('cancels pending reloads and unsubscribes when navigating away', () => {
    const { unmount } = renderHook(() => useInertiaCable('signed'))
    act(() => callbacks.received(refresh))
    unmount()
    act(() => vi.runAllTimers())
    expect(unsubscribe).toHaveBeenCalledOnce()
    expect(router.reload).not.toHaveBeenCalled()
  })

  it('cancels the old stream refresh when the stream changes', () => {
    const { rerender } = renderHook(({ stream }) => useInertiaCable(stream), {
      initialProps: { stream: 'first' },
    })
    act(() => callbacks.received(refresh))
    rerender({ stream: 'second' })
    act(() => {
      callbacks.connected()
      vi.runAllTimers()
    })
    expect(unsubscribe).toHaveBeenCalledOnce()
    expect(subscribe).toHaveBeenLastCalledWith(
      { channel: 'InertiaCable::StreamChannel', signed_stream_name: 'second' },
      expect.any(Object),
    )
    expect(router.reload).not.toHaveBeenCalled()
  })

  it('does not subscribe while disabled or without a token', () => {
    renderHook(() => useInertiaCable('signed', { enabled: false }))
    renderHook(() => useInertiaCable(null))
    expect(subscribe).not.toHaveBeenCalled()
  })

  it('cleans up React 19 StrictMode subscriptions', () => {
    configure({ reactStrictMode: true })
    const { unmount } = renderHook(() => useInertiaCable('signed'))
    expect(subscribe).toHaveBeenCalledTimes(2)
    expect(unsubscribe).toHaveBeenCalledTimes(1)
    unmount()
    expect(unsubscribe).toHaveBeenCalledTimes(2)
  })
})
