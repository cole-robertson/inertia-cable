// @vitest-environment jsdom
import {
  http,
  HttpCancelledError,
  type HttpRequestConfig,
  type HttpResponse,
  type Page,
} from "@inertiajs/core"
import { router } from "@inertiajs/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { createInertiaRefresh } from "../src/createInertiaRefresh"

interface Pending {
  config: HttpRequestConfig
  resolve: (response: HttpResponse) => void
}

const page = {
  component: "Inbox",
  url: "/org/inbox?site_id=1",
  version: null,
  props: { errors: {}, arrivals: ["old"], counts: 1 },
  flash: {},
  rescuedProps: [],
  rememberedState: {},
} as Page

let requests: Pending[]
let swap = vi.fn(async () => {})
let coordinator: ReturnType<typeof createInertiaRefresh>
let originalClient: ReturnType<typeof http.getClient>

async function tick(ms = 110) {
  await vi.advanceTimersByTimeAsync(ms)
}

function respond(
  index: number,
  props: Record<string, unknown>,
  url = page.url,
) {
  requests[index].resolve({
    status: 200,
    headers: { "x-inertia": "true", "content-type": "application/json" },
    data: JSON.stringify({ ...page, url, props }),
  })
}

beforeEach(async () => {
  vi.useFakeTimers()
  vi.spyOn(window, "scrollTo").mockImplementation(() => {})
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible")
  window.history.replaceState({}, "", page.url)
  requests = []
  swap = vi.fn(async () => {})
  router.init({
    initialPage: page,
    resolveComponent: async () => () => null,
    swapComponent: swap,
  })
  await tick(0)
  originalClient = http.getClient()
  http.setClient({
    request: (config) =>
      new Promise((resolve, reject) => {
        requests.push({ config, resolve })
        config.signal?.addEventListener("abort", () =>
          reject(new HttpCancelledError("Cancelled")),
        )
      }),
  })
  coordinator = createInertiaRefresh({
    only: ["arrivals"],
    pollInterval: 60_000,
  })
})

afterEach(async () => {
  coordinator.dispose()
  router.cancelAll()
  await tick(0)
  http.setClient(originalClient)
  vi.restoreAllMocks()
  vi.useRealTimers()
})

describe("Inertia 3 refresh coordination", () => {
  it("merges prop keys from independent subscriptions and reports freshness after completion", async () => {
    const changed = vi.fn()
    const unsubscribe = coordinator.subscribe(changed)
    coordinator.refresh(["arrivals"])
    coordinator.refresh(["counts", "arrivals"])
    expect(coordinator.getSnapshot().lastRefreshedAt).toBeNull()
    await tick()
    expect(requests).toHaveLength(1)
    expect(requests[0].config.headers?.["X-Inertia-Partial-Data"]).toBe("arrivals,counts")
    expect(coordinator.getSnapshot().refreshing).toBe(true)
    respond(0, { arrivals: ["updated"], counts: 2 })
    await tick(0)
    expect(coordinator.getSnapshot().refreshing).toBe(false)
    expect(coordinator.getSnapshot().lastRefreshedAt).not.toBeNull()
    expect(changed).toHaveBeenCalled()
    unsubscribe()
  })
  it("waits for an already-processing response before applying a scope navigation", async () => {
    const navigate = vi.fn(() => router.get("/org/inbox?site_id=2"))
    const remove = router.on("beforeUpdate", ({ detail }) => {
      const arrivals = detail.page.props.arrivals
      if (Array.isArray(arrivals) && arrivals[0] === "processing") {
        // Inertia has received the response, so its cancel token is a no-op.
        coordinator.visit(navigate)
        expect(navigate).not.toHaveBeenCalled()
      }
    })
    try {
      coordinator.refresh()
      await tick()
      respond(0, { arrivals: ["processing"] })
      await tick()
      expect(navigate).toHaveBeenCalledOnce()
      expect(requests).toHaveLength(2)
      respond(1, { arrivals: ["site two"] }, "/org/inbox?site_id=2")
      await tick(0)
      expect(swap).toHaveBeenLastCalledWith(
        expect.objectContaining({
          page: expect.objectContaining({
            url: "/org/inbox?site_id=2",
            props: expect.objectContaining({ arrivals: ["site two"] }),
          }),
        }),
      )
    } finally {
      remove()
    }
  })

  it("combines signals and retains one trailing refresh during a slow request", async () => {
    coordinator.refresh()
    coordinator.refresh(["counts"])
    await tick()
    expect(requests).toHaveLength(1)
    expect(requests[0].config.headers?.["X-Inertia-Partial-Data"]).toBe(
      "arrivals,counts",
    )
    coordinator.refresh()
    coordinator.refresh()
    await tick()
    expect(requests).toHaveLength(1)
    respond(0, { arrivals: ["updated"], counts: 2 })
    await tick()
    expect(requests).toHaveLength(2)
    respond(1, { arrivals: ["newest"] })
    await tick()
    expect(requests).toHaveLength(2)
  })

  it("cancels the old reload before a same-path site switch and rejects its late response", async () => {
    coordinator.refresh()
    await tick()
    router.get(
      "/org/inbox?site_id=2",
      {},
      { only: ["arrivals"], preserveState: true },
    )
    await tick(0)
    expect(requests[0].config.signal?.aborted).toBe(true)
    expect(requests[1].config.signal?.aborted).toBe(false)
    respond(1, { arrivals: ["site two"] }, "/org/inbox?site_id=2")
    await tick(0)
    respond(0, { arrivals: ["stale site one"] })
    await tick(0)
    expect(swap).toHaveBeenLastCalledWith(
      expect.objectContaining({
        page: expect.objectContaining({
          props: expect.objectContaining({ arrivals: ["site two"] }),
        }),
      }),
    )
    await tick()
    expect(requests[2].config.url).toContain("site_id=2")
  })

  it("lets form submissions finish and preserves their errors on the queued refresh", async () => {
    router.post("/org/inbox?site_id=1", { body: "draft" })
    await tick(0)
    coordinator.refresh()
    await tick()
    expect(requests).toHaveLength(1)
    expect(requests[0].config.signal?.aborted).toBe(false)
    respond(0, { errors: { body: "Check this entry" }, arrivals: ["old"] })
    await tick()
    expect(requests).toHaveLength(2)
    respond(1, { errors: {}, arrivals: ["fresh"] })
    await tick(0)
    expect(swap).toHaveBeenLastCalledWith(
      expect.objectContaining({
        preserveState: true,
        page: expect.objectContaining({
          props: expect.objectContaining({
            errors: { body: "Check this entry" },
            arrivals: ["fresh"],
          }),
        }),
      }),
    )
  })

  it("uses Inertia rest-mode polling as a fallback without overlapping cable reloads", async () => {
    await tick(60_000)
    expect(requests).toHaveLength(1)
    coordinator.refresh()
    await tick(120_000)
    expect(requests).toHaveLength(1)
    respond(0, { arrivals: ["polled"] })
    await tick()
    expect(requests).toHaveLength(2)
    respond(1, { arrivals: ["signaled"] })
    await tick(60_000)
    expect(requests).toHaveLength(3)
  })

  it("defers hidden-tab work and catches up once on visibility", async () => {
    vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden")
    document.dispatchEvent(new Event("visibilitychange"))
    coordinator.refresh()
    await tick(120_000)
    expect(requests).toHaveLength(0)
    vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible")
    document.dispatchEvent(new Event("visibilitychange"))
    await tick()
    expect(requests).toHaveLength(1)
  })

  it("cancels only its own request and removes polling on scope teardown", async () => {
    coordinator.refresh()
    await tick()
    coordinator.dispose()
    expect(requests[0].config.signal?.aborted).toBe(true)
    await tick(120_000)
    expect(requests).toHaveLength(1)
    expect(router.activePolls).toBe(0)
  })

  it("does not get stuck behind a navigation vetoed by a leave guard", async () => {
    const remove = router.on("before", (event) => {
      if (event.detail.visit.url.search.includes("site_id=2")) return false
    })
    try {
      router.get("/org/inbox?site_id=2")
      await tick(0)
      coordinator.refresh()
      await tick()
      expect(requests).toHaveLength(1)
      expect(requests[0].config.url).toContain("site_id=1")
    } finally {
      remove()
    }
  })
})
