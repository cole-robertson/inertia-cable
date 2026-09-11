import type { ReloadOptions } from "@inertiajs/core"
import { router } from "@inertiajs/react"

export interface RefreshOptions {
  only: string[]
  debounce?: number
  pollInterval?: number
}

export interface RefreshState {
  refreshing: boolean
  lastRefreshedAt: number | null
  error: string | null
}

interface RefreshRequest {
  id?: string
  cancel?: () => void
  only: string[]
}

/**
 * Coordinate external invalidations for ONE mounted page scope. Inertia owns
 * HTTP, prop merging, optimistic state, polling and cancellation. We only
 * combine invalidations and yield our own requests to user visits.
 *
 * 3.7 deliberately compares partial reload URLs without the query string.
 * Cancel our reload before another visit starts so a previous site/filter
 * response cannot overwrite the new selection. Never use router.cancelAll:
 * that also cancels forms, optimistic updates and unrelated background work.
 */
export function createInertiaRefresh({
  only,
  debounce = 100,
  pollInterval,
}: RefreshOptions) {
  let snapshot: RefreshState = { refreshing: false, lastRefreshedAt: null, error: null }
  const listeners = new Set<() => void>()
  function update(next: Partial<RefreshState>) {
    snapshot = { ...snapshot, ...next }
    listeners.forEach((listener) => listener())
  }
  let disposed = false
  let active: RefreshRequest | null = null
  let preparingId: string | undefined
  let pendingVisit: (() => void) | undefined
  let timer: ReturnType<typeof setTimeout> | undefined
  const pending = new Set<string>()
  const visits = new Map<string, string>()
  const pathname = window.location.pathname
  let polling = false
  let poll: ReturnType<typeof router.poll> | undefined

  const visible = () => document.visibilityState !== "hidden"
  const canRun = () =>
    !disposed &&
    visible() &&
    visits.size === 0 &&
    window.location.pathname === pathname

  function stopPolling() {
    poll?.stop()
    polling = false
  }

  function startPolling() {
    if (poll && !polling && canRun() && !active) {
      poll.start()
      polling = true
    }
  }

  function cancelActive() {
    const request = active
    if (!request) return
    request.only.forEach((key) => pending.add(key))
    request.cancel?.()
    // Inertia may already be processing a response, when its cancel token
    // intentionally does nothing. Its onFinish still owns clearing active.
  }

  function schedule() {
    if (!canRun() || active || timer) return
    if (pendingVisit) {
      const run = pendingVisit
      pendingVisit = undefined
      run()
      return
    }
    if (pending.size === 0) {
      startPolling()
      return
    }
    timer = setTimeout(() => {
      timer = undefined
      if (!canRun() || active) return
      const keys = [...pending]
      pending.clear()
      const request: RefreshRequest = { only: keys }
      router.reload(requestOptions(request))
      // A leave-confirmation handler may veto the visit before it starts.
      // Retain the invalidation, but do not retry in a tight loop.
      if (!request.cancel) {
        keys.forEach((key) => pending.add(key))
        startPolling()
      }
    }, debounce)
  }

  function requestOptions(request: RefreshRequest): ReloadOptions {
    return {
      only: request.only,
      preserveErrors: true,
      preserveUrl: true,
      onBefore: (visit) => {
        if (!canRun() || active) {
          request.only.forEach((key) => pending.add(key))
          stopPolling()
          return false
        }
        request.id = visit.id
        preparingId = visit.id
      },
      onCancelToken: (token) => {
        active = request
        update({ refreshing: true, error: null })
        request.cancel = token.cancel
        stopPolling()
      },
      onSuccess: () => {
        if (!disposed && active === request) update({ lastRefreshedAt: Date.now(), error: null })
      },
      onError: () => {
        // Preserved form errors still accompany a successfully applied page.
        if (!disposed && active === request) update({ lastRefreshedAt: Date.now(), error: null })
      },
      onNetworkError: () => {
        if (!disposed && active === request) update({ error: "Refresh failed. Retrying on the next update." })
      },
      onFinish: () => {
        if (active !== request) return
        active = null
        if (!disposed) update({ refreshing: false })
        schedule()
      },
    }
  }

  function refresh(keys = only) {
    if (disposed) return
    keys.forEach((key) => pending.add(key))
    schedule()
  }

  // Scope-changing controls use this explicit barrier. Cancellation becomes a
  // no-op once Inertia is processing a response; in that case onFinish runs the
  // navigation after the old response has settled. Keep the caller's closure
  // rather than reconstructing a visit and losing its callbacks.
  function visit(run: () => void) {
    if (disposed) return
    pendingVisit = run
    clearTimeout(timer)
    timer = undefined
    stopPolling()
    cancelActive()
    schedule()
  }

  // `before` also covers visits served from prefetch (which have no start).
  const removeBefore = router.on("before", (event) => {
    const visit = event.detail.visit
    if (event.defaultPrevented || visit.id === active?.id || visit.prefetch)
      return
    // Our onBefore runs before this event, but onCancelToken runs after it.
    if (visit.id === preparingId) return
    visits.set(visit.id, visit.url.href)
    stopPolling()
    cancelActive()
    queueMicrotask(() => {
      if (event.defaultPrevented) {
        visits.delete(visit.id)
        schedule()
      }
    })
  })
  const removeStart = router.on("start", ({ detail: { visit } }) => {
    if (visit.id === active?.id || visit.prefetch) return
    if (visit.cancelled || visit.interrupted) return
    visits.set(visit.id, visit.url.href)
    stopPolling()
    cancelActive()
  })
  const removeFinish = router.on("finish", ({ detail: { visit } }) => {
    visits.delete(visit.id)
    schedule()
  })
  const removeSuccess = router.on("success", ({ detail }) => {
    if (detail.visitId) visits.delete(detail.visitId)
    schedule()
  })
  const removeError = router.on("error", ({ detail }) => {
    if (detail.visitId) visits.delete(detail.visitId)
    schedule()
  })
  const removeNetworkError = router.on("networkError", ({ detail }) => {
    const url = "url" in detail.error ? detail.error.url : undefined
    for (const [id, href] of visits) {
      if (href.split("#")[0] === url) visits.delete(id)
    }
    schedule()
  })

  function onVisibility() {
    if (!visible()) {
      stopPolling()
      return
    }
    // Also covers missed server signals while the tab was suspended.
    refresh()
  }
  function onPopState() {
    cancelActive()
    refresh()
  }
  document.addEventListener("visibilitychange", onVisibility)
  window.addEventListener("popstate", onPopState)

  if (pollInterval) {
    // Built-in rest-mode polling supplies the fallback clock and avoids
    // overlapping timer requests. Cable signals use the same request lifecycle.
    poll = router.poll(pollInterval, () => requestOptions({ only }), {
      autoStart: false,
      mode: "rest",
    })
    startPolling()
  }

  return {
    refresh,
    visit,
    getSnapshot: () => snapshot,
    subscribe(listener: () => void) {
      listeners.add(listener)
      return () => { listeners.delete(listener) }
    },
    dispose() {
      disposed = true
      clearTimeout(timer)
      removeStart()
      removeBefore()
      removeFinish()
      removeSuccess()
      removeError()
      removeNetworkError()
      document.removeEventListener("visibilitychange", onVisibility)
      window.removeEventListener("popstate", onPopState)
      poll?.destroy()
      active?.cancel?.()
      listeners.clear()
      pending.clear()
      pendingVisit = undefined
    },
  }
}
