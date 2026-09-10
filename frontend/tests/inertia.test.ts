import { http, type HttpClient, type HttpResponse, type Page } from '@inertiajs/core'
import { router } from '@inertiajs/react'
import type { Consumer } from '@rails/actioncable'
import { act, cleanup, renderHook, waitFor } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { setConsumer } from '../src/consumer'
import { useInertiaCable, type CablePayload } from '../src/useInertiaCable'

afterEach(() => {
  cleanup()
  router.cancelAll()
})

it('refreshes through Inertia 3 while preserving errors, component state, and pending optimistic updates', async () => {
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  let receive!: (data: CablePayload) => void
  setConsumer({
    subscriptions: {
      create: (_identifier: unknown, handlers: { received: typeof receive }) => {
        receive = handlers.received
        return { unsubscribe: vi.fn() }
      },
    },
  } as unknown as Consumer)

  const initialPage = {
    component: 'Chat', url: '/', version: null, flash: {}, rescuedProps: [], rememberedState: {},
    props: {
      // Inertia types errors as both flat errors and named bags; Rails sends flat errors here.
      errors: { body: 'Cannot be blank' } as unknown as Page['props']['errors'],
      messages: ['old'], title: 'Chat',
    },
  }
  const swapComponent = vi.fn(async () => {})
  const component = () => null
  router.init({ initialPage, resolveComponent: async () => component, swapComponent })
  await waitFor(() => expect(swapComponent).toHaveBeenCalled())
  swapComponent.mockClear()

  const request = vi.fn<HttpClient['request']>(async () => ({
    status: 200,
    headers: { 'x-inertia': 'true', 'content-type': 'application/json' },
    data: JSON.stringify({ ...initialPage, props: { errors: {}, messages: ['new'] } }),
  }))
  const previousClient = http.getClient()
  const onReloadFinish = vi.fn()
  const removeFinishListener = router.on('finish', (event) => {
    if (event.detail.visit.method === 'get') onReloadFinish()
  })
  http.setClient({ request })
  try {
    renderHook(() => useInertiaCable('signed', { only: ['messages'], debounce: 0 }))
    act(() => receive({ type: 'refresh', model: 'Message', id: 1, action: 'create', timestamp: '' }))

    await waitFor(() => expect(swapComponent).toHaveBeenCalledWith(expect.objectContaining({
      component,
      preserveState: true,
      page: expect.objectContaining({
        props: { errors: { body: 'Cannot be blank' }, messages: ['new'], title: 'Chat' },
      }),
    })))
    expect(request).toHaveBeenCalledWith(expect.objectContaining({
      method: 'get',
      headers: expect.objectContaining({
        'X-Inertia-Partial-Component': 'Chat',
        'X-Inertia-Partial-Data': 'messages',
      }),
    }))

    let finishMutation!: (response: HttpResponse) => void
    request.mockImplementationOnce(() => new Promise((resolve) => { finishMutation = resolve }))
    const onFinish = vi.fn()
    act(() => router.post('/', {}, {
      optimistic: (props) => ({ messages: [...(props.messages as string[]), 'pending'] }),
      onFinish,
    }))
    await waitFor(() => expect(swapComponent).toHaveBeenLastCalledWith(expect.objectContaining({
      page: expect.objectContaining({ props: expect.objectContaining({ messages: ['new', 'pending'] }) }),
    })))

    // Another user's broadcast arrives while our optimistic mutation is still pending.
    const requestsBeforeRefresh = request.mock.calls.length
    onReloadFinish.mockClear()
    act(() => receive({ type: 'refresh', model: 'Message', id: 2, action: 'create', timestamp: '' }))
    await waitFor(() => expect(request).toHaveBeenCalledTimes(requestsBeforeRefresh + 1))
    await waitFor(() => expect(onReloadFinish).toHaveBeenCalledOnce())
    expect(swapComponent).toHaveBeenLastCalledWith(expect.objectContaining({
      page: expect.objectContaining({ props: expect.objectContaining({ messages: ['new', 'pending'] }) }),
    }))

    finishMutation({
      status: 200,
      headers: { 'x-inertia': 'true', 'content-type': 'application/json' },
      data: JSON.stringify({ ...initialPage, props: { errors: {}, messages: ['new', 'saved'] } }),
    })
    await waitFor(() => expect(onFinish).toHaveBeenCalledOnce())
    expect(swapComponent).toHaveBeenLastCalledWith(expect.objectContaining({
      page: expect.objectContaining({ props: expect.objectContaining({ messages: ['new', 'saved'] }) }),
    }))
  } finally {
    removeFinishListener()
    http.setClient(previousClient)
  }
})
