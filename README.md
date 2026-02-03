# InertiaCable

ActionCable broadcast DSL for [Inertia.js](https://inertiajs.com/) Rails applications. Three lines of code to get real-time updates.

InertiaCable broadcasts lightweight JSON signals over ActionCable. The client receives them and calls `router.reload()` to re-fetch props through Inertia's normal HTTP flow. The server remains the single source of truth — no manual JSON serialization, no duplicated rendering logic, no WebSocket payloads to maintain.

```
Model save → after_commit → ActionCable broadcast (JSON signal)
                                    ↓
React hook subscribes → receives signal → router.reload({ only: ['messages'] })
                                    ↓
Inertia HTTP request → controller re-evaluates props → React re-renders
```

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Model DSL](#model-dsl)
- [Controller Helper](#controller-helper)
- [React Hook](#react-hook)
- [Suppressing Broadcasts](#suppressing-broadcasts)
- [Server-Side Debounce](#server-side-debounce)
- [Testing](#testing)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Security](#security)
- [TypeScript Types](#typescript-types)
- [Advanced React Patterns](#advanced-react-patterns)
- [Troubleshooting](#troubleshooting)
- [Requirements](#requirements)
- [Development](#development)
- [License](#license)

## Installation

Add the gem to your Gemfile:

```ruby
gem "inertia_cable"
```

Install the frontend package:

```bash
npm install @inertia-cable/react @rails/actioncable
```

Run the install generator (optional):

```bash
rails generate inertia_cable:install
```

## Quick Start

### 1. Model — declare what broadcasts

```ruby
class Message < ApplicationRecord
  belongs_to :chat
  broadcasts_to :chat
end
```

### 2. Controller — pass a signed stream token as a prop

```ruby
class ChatsController < ApplicationController
  def show
    chat = Chat.find(params[:id])
    render inertia: 'Chats/Show', props: {
      chat: chat.as_json,
      messages: -> { chat.messages.order(:created_at).as_json },
      cable_stream: inertia_cable_stream(chat)
    }
  end
end
```

### 3. React — subscribe to the stream

```tsx
import { useInertiaCable } from '@inertia-cable/react'

export default function ChatShow({ chat, messages, cable_stream }) {
  useInertiaCable(cable_stream, { only: ['messages'] })

  return (
    <div>
      <h1>{chat.name}</h1>
      {messages.map(msg => <Message key={msg.id} message={msg} />)}
    </div>
  )
}
```

That's it. When any user creates, updates, or deletes a message, all connected clients automatically reload the `messages` prop.

---

## Model DSL

### `broadcasts_to`

Broadcasts a refresh signal to a named stream whenever the model is committed. Uses a single `after_commit` callback.

```ruby
class Post < ApplicationRecord
  belongs_to :board

  # Stream to the associated record (calls post.board to resolve)
  broadcasts_to :board

  # Stream to a lambda (receives the record as argument)
  broadcasts_to ->(post) { [post.board, :posts] }

  # Stream to a static string
  broadcasts_to "global_feed"
end
```

> **Note:** `broadcasts_refreshes_to` is available as a legacy alias if you prefer the Turbo-style naming. All options are identical.

#### Stream resolution

| Argument | How it resolves |
|----------|----------------|
| `:symbol` | Calls the method on the record (`post.board`) |
| `Proc` / `lambda` | Calls with the record (`->(post) { ... }`) |
| `String` | Used as-is |
| ActiveRecord model | Uses GlobalID (`gid://app/Board/1`) |
| `Array` | Joins elements with `:` after resolving each |

#### `on:` — selective events

By default, broadcasts fire on create, update, and destroy. Use `on:` to limit:

```ruby
class Post < ApplicationRecord
  # Only broadcast when a post is created or destroyed — skip updates
  broadcasts_to :board, on: [:create, :destroy]
end
```

#### `if:` / `unless:` — conditional broadcasts

Standard Rails callback conditions:

```ruby
class Post < ApplicationRecord
  # Only broadcast published posts
  broadcasts_to :board, if: :published?

  # Skip draft posts
  broadcasts_to :board, unless: -> { draft? }
end
```

All options compose:

```ruby
class Post < ApplicationRecord
  broadcasts_to :board, on: [:create, :destroy], if: :published?
end
```

#### `extra:` — custom payload fields

Attach additional data to the broadcast payload. Accepts a `Hash` or a `Proc` that receives the record:

```ruby
class Post < ApplicationRecord
  # Static extra fields
  broadcasts_to :board, extra: { priority: "high" }

  # Dynamic extra fields (proc receives the record)
  broadcasts_to :board, extra: ->(post) { { category: post.category } }
end
```

The extra data appears in the `extra` field of the broadcast payload and is available to the `onRefresh` callback on the client.

#### `debounce:` — per-model server-side debounce

Route broadcasts through `InertiaCable::Debounce` instead of the default async job:

```ruby
class Post < ApplicationRecord
  # Use global InertiaCable.debounce_delay
  broadcasts_to :board, debounce: true

  # Custom delay in seconds
  broadcasts_to :board, debounce: 1.0
end
```

This requires a shared cache store (Redis, Memcached, or SolidCache) in multi-process deployments.

### `broadcasts`

Convention-based version that broadcasts to `model_name.plural` (e.g., `"posts"`):

```ruby
class Post < ApplicationRecord
  broadcasts                           # broadcasts to "posts"
  broadcasts on: [:create, :destroy]   # with options
end
```

> **Note:** `broadcasts_refreshes` is available as a legacy alias.

### Instance methods

All instance methods accept splat arguments for compound streams:

```ruby
post = Post.find(1)

# Sync — broadcast immediately
post.broadcast_refresh_to(board)             # single stream
post.broadcast_refresh_to(board, :posts)     # compound stream (board:posts)
post.broadcast_refresh                       # to model_name.plural

# Async — via ActiveJob
post.broadcast_refresh_later_to(board)
post.broadcast_refresh_later_to(board, :posts)
post.broadcast_refresh_later

# With extra payload data
post.broadcast_refresh_to(board, extra: { priority: "high" })
post.broadcast_refresh_later_to(board, extra: { priority: "high" })

# With debounce
post.broadcast_refresh_later_to(board, debounce: true)
post.broadcast_refresh_later_to(board, debounce: 2.0)

# With inline condition (block)
post.broadcast_refresh_to(board) { published? }
post.broadcast_refresh_later_to(board) { visible? }
```

When a block is given, the broadcast is skipped if the block returns a falsy value. The block is evaluated in the context of the record instance.

### Broadcast payload

Every broadcast sends this JSON:

```json
{
  "type": "refresh",
  "model": "Message",
  "id": 42,
  "action": "create",
  "timestamp": "2026-02-02T18:15:19+00:00"
}
```

When `extra:` is used, an additional field is included:

```json
{
  "type": "refresh",
  "model": "Message",
  "id": 42,
  "action": "create",
  "timestamp": "2026-02-02T18:15:19+00:00",
  "extra": { "priority": "high" }
}
```

The `action` field is inferred from the record state: `"create"`, `"update"`, or `"destroy"`.

---

## Controller Helper

`inertia_cable_stream` generates a cryptographically signed stream token. Pass it as an Inertia prop.

```ruby
# Single model (uses GlobalID)
inertia_cable_stream(chat)                # signed "gid://app/Chat/1"

# String
inertia_cable_stream("posts")             # signed "posts"

# Compound (splat args, joined with ":")
inertia_cable_stream(chat, :messages)     # signed "gid://app/Chat/1:messages"
```

The token is verified server-side when the client subscribes, preventing unauthorized stream access.

#### Stream resolution details

Each element in a stream is resolved individually:

- **`to_gid_param` vs `to_param`**: If an object responds to `to_gid_param` (ActiveRecord models), that is used. Otherwise `to_param` is called. This means you can pass plain strings, symbols, or models interchangeably.
- **Nested arrays are flattened**: `[board, [:posts, :active]]` becomes `"gid://app/Board/1:posts:active"`.
- **`nil` and blank elements are stripped**: `[board, nil, :posts]` becomes `"gid://app/Board/1:posts"`.

```ruby
inertia_cable_stream(board)                       # → signed "gid://app/Board/1"
inertia_cable_stream(:posts)                      # → signed "posts"
inertia_cable_stream(board, [:posts, :active])    # → signed "gid://app/Board/1:posts:active"
inertia_cable_stream(board, nil, :posts)          # → signed "gid://app/Board/1:posts"
```

---

## React Hook

> **Note:** Only the React adapter (`@inertia-cable/react`) is available. The server-side gem works with any Inertia frontend, but the client hook is React-only. Vue and Svelte adapters are welcome as community contributions.

### `useInertiaCable(signedStreamName, options?)`

Returns `{ connected }` — a boolean indicating whether the WebSocket subscription is currently active.

```tsx
const { connected } = useInertiaCable(cable_stream, {
  // Only reload these props (passed to router.reload)
  only: ['messages'],

  // Reload all props except these
  except: ['metadata'],

  // Callback fired on every refresh signal (before reload)
  onRefresh: (data) => {
    console.log(`${data.model} #${data.id} was ${data.action}`)
  },

  // Connection lifecycle callbacks
  onConnected: () => console.log('subscribed'),
  onDisconnected: () => console.log('lost connection'),

  // Client-side debounce in ms (default: 100)
  // Coalesces rapid signals into a single reload
  debounce: 200,

  // Disable/enable the subscription (default: true)
  enabled: isVisible,
})

// Show a reconnecting indicator
if (!connected) {
  return <Banner>Reconnecting…</Banner>
}
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `string[]` | — | Only reload these props |
| `except` | `string[]` | — | Reload all props except these |
| `onRefresh` | `(data) => void` | — | Callback before each reload |
| `onConnected` | `() => void` | — | Called when subscription connects |
| `onDisconnected` | `() => void` | — | Called when connection drops |
| `debounce` | `number` | `100` | Debounce delay in ms |
| `enabled` | `boolean` | `true` | Enable/disable subscription |

| Return | Type | Description |
|--------|------|-------------|
| `connected` | `boolean` | Whether the subscription is connected |

### Automatic catch-up on reconnection

When a WebSocket connection drops and reconnects (e.g., after a network interruption or backgrounded tab), the hook automatically triggers a `router.reload()` to catch up on any changes that were missed while disconnected. This only fires on *re*connection — not on the initial connection.

**Why it works:** ActionCable handles reconnection automatically (with exponential backoff). The hook tracks whether it has connected before via a ref (`hasConnectedRef`). On the first `connected()` callback, it sets the flag; on subsequent `connected()` callbacks, it knows a disconnect happened and triggers a reload. The reload is debounced through the same timer, so even if reconnection triggers alongside a real broadcast signal, only one reload fires.

### `InertiaCableProvider`

Optional context provider for a custom ActionCable consumer. Use it when you need:

- A custom cable URL (different from the default `/cable`)
- A separate cable server (e.g., `wss://cable.example.com/cable`)
- An authenticated WebSocket endpoint

```tsx
import { InertiaCableProvider } from '@inertia-cable/react'
import { createInertiaApp } from '@inertiajs/react'

createInertiaApp({
  // ...
  setup({ el, App, props }) {
    createRoot(el).render(
      <InertiaCableProvider url="wss://cable.example.com/cable">
        <App {...props} />
      </InertiaCableProvider>
    )
  },
})
```

**Fallback behavior:** If no `InertiaCableProvider` is present in the component tree, the hook falls back to a module-level singleton consumer (created via `getConsumer()`), which connects to the default `/cable` endpoint. You only need the provider when the default isn't sufficient.

### `getConsumer` / `setConsumer`

Low-level access to the ActionCable consumer singleton:

```typescript
import { getConsumer, setConsumer } from '@inertia-cable/react'

const consumer = getConsumer()       // get or create
setConsumer(myCustomConsumer)        // replace
```

---

## Suppressing Broadcasts

Two levels of suppression, both thread-safe and nestable:

```ruby
# Global — suppress all models
InertiaCable.suppressing_broadcasts do
  1000.times { Post.create!(title: "Imported") }
end

# Class-level — suppress via the model class
Post.suppressing_broadcasts do
  Post.create!(title: "Silent")
end
```

---

## Server-Side Debounce

Optionally coalesce rapid broadcasts using Rails cache. This is **not used by default** — the standard broadcast path (`InertiaCable.broadcast`) sends every signal, and the client-side 100ms debounce handles coalescing for most use cases.

When you do use it, it requires a shared cache store (Redis, Memcached, or SolidCache) in multi-process deployments. The default `MemoryStore` only works within a single process.

```ruby
InertiaCable.debounce_delay = 0.5  # seconds (default)

# Use debounced broadcast explicitly
InertiaCable::Debounce.broadcast("my_stream", payload)

# With custom delay override
InertiaCable::Debounce.broadcast("my_stream", payload, delay: 2.0)
```

---

## Testing

InertiaCable ships a `TestHelper` module for asserting broadcasts:

```ruby
class MessageTest < ActiveSupport::TestCase
  include InertiaCable::TestHelper

  test "broadcasting on create" do
    chat = chats(:general)

    assert_broadcasts_on(chat) do
      Message.create!(chat: chat, body: "hello")
    end
  end

  test "exact broadcast count" do
    chat = chats(:general)

    assert_broadcasts_on(chat, count: 1) do
      Message.create!(chat: chat, body: "hello")
    end
  end

  test "no broadcasts when suppressed" do
    chat = chats(:general)

    assert_no_broadcasts_on(chat) do
      Message.suppressing_broadcasts do
        Message.create!(chat: chat, body: "silent")
      end
    end
  end

  test "inspect broadcast payloads" do
    chat = chats(:general)

    payloads = capture_broadcasts_on(chat) do
      Message.create!(chat: chat, body: "hello")
    end

    assert_equal "create", payloads.first[:action]
    assert_equal "Message", payloads.first[:model]
  end
end
```

### Test helper methods

| Method | Description |
|--------|-------------|
| `assert_broadcasts_on(*streamables, count: nil) { }` | Assert broadcasts occurred |
| `assert_no_broadcasts_on(*streamables) { }` | Assert no broadcasts occurred |
| `capture_broadcasts_on(*streamables) { }` | Capture and return payload array |

All three accept splat streamables: `assert_broadcasts_on(chat, :messages) { ... }`

---

## Configuration

```ruby
# config/initializers/inertia_cable.rb

# Custom signing key (defaults to Rails secret_key_base + "inertia_cable")
InertiaCable.signed_stream_verifier_key = "custom_key"

# Server-side debounce delay
InertiaCable.debounce_delay = 0.5
```

---

## How It Works

1. **Model saves** → `after_commit` callback fires
2. **BroadcastJob** enqueues (async via ActiveJob)
3. **ActionCable** broadcasts `{ type: "refresh", model: "Message", id: 42, action: "create", ... }` to the signed stream
4. **`useInertiaCable`** hook receives the signal, debounces, then calls `router.reload({ only: ['messages'] })`
5. **Inertia** makes a normal HTTP request to the controller
6. **Controller** re-evaluates lazy props and returns fresh data
7. **React** re-renders with new props

The key insight: no data is sent over the WebSocket. It's purely a notification channel. All data flows through Inertia's existing HTTP request cycle, so your controller remains the single source of truth.

---

## Security

InertiaCable uses Rails' `MessageVerifier` (HMAC-SHA256) to sign stream tokens. Here's how the security model works:

- **Stream tokens are signed** using `secret_key_base` (plus a purpose-specific salt). The token generated by `inertia_cable_stream(chat)` in the controller is a cryptographic signature over the stream name — it cannot be forged or tampered with.
- **Tokens are verified server-side** when the client subscribes via `StreamChannel`. If the signature is invalid or has been altered, the subscription is rejected immediately.
- **No data travels over the WebSocket.** The broadcast payload is a lightweight signal (`{ type: "refresh", ... }`). Actual data is fetched via Inertia's normal HTTP cycle, which goes through your controller (and its authorization logic) on every reload.
- **Rotate `secret_key_base`** per Rails defaults. If you use Rails' built-in credentials or `secret_key_base` rotation, stream tokens rotate automatically. Existing WebSocket subscriptions continue to work until they reconnect.

---

## TypeScript Types

The following types are exported from `@inertia-cable/react` and can be imported for use in your application:

```typescript
import type {
  RefreshPayload,
  UseInertiaCableOptions,
  UseInertiaCableReturn,
} from '@inertia-cable/react'

import type { InertiaCableProviderProps } from '@inertia-cable/react'
```

| Type | Description |
|------|-------------|
| `RefreshPayload` | Shape of the broadcast signal (`type`, `model`, `id`, `action`, `timestamp`, `extra?`) |
| `UseInertiaCableOptions` | Options accepted by `useInertiaCable` (`only`, `except`, `onRefresh`, etc.) |
| `UseInertiaCableReturn` | Return value of `useInertiaCable` (`{ connected }`) |
| `InertiaCableProviderProps` | Props for `InertiaCableProvider` (`url?`, `children`) |

---

## Advanced React Patterns

### Conditional subscription with `enabled`

Pause the subscription when the component isn't visible or relevant:

```tsx
function ChatShow({ chat, messages, cable_stream }) {
  const isVisible = usePageVisibility()

  useInertiaCable(cable_stream, {
    only: ['messages'],
    enabled: isVisible, // pauses subscription when tab is hidden
  })

  return <MessageList messages={messages} />
}
```

### Multiple hooks on one page

Subscribe to different streams for different prop groups:

```tsx
function Dashboard({ stats, notifications, stats_stream, notifications_stream }) {
  useInertiaCable(stats_stream, { only: ['stats'] })
  useInertiaCable(notifications_stream, { only: ['notifications'] })

  return (
    <>
      <StatsPanel stats={stats} />
      <NotificationList notifications={notifications} />
    </>
  )
}
```

### Custom `onRefresh` for optimistic UI or toast notifications

Use the callback to trigger side effects before the reload:

```tsx
function ChatShow({ chat, messages, cable_stream }) {
  useInertiaCable(cable_stream, {
    only: ['messages'],
    onRefresh: (data) => {
      if (data.action === 'create') {
        toast.info('New message received')
      }
      // Access extra payload data if the server sent it
      if (data.extra?.priority === 'high') {
        toast.warn('High priority update!')
      }
    },
  })

  return <MessageList messages={messages} />
}
```

---

## Troubleshooting

### `router.reload()` crashes with `only`/`except`

Pass arrays, not `undefined`. If you conditionally set `only` or `except`, make sure you pass an actual array or omit the option entirely:

```tsx
// Bad — passing undefined crashes router.reload()
useInertiaCable(stream, { only: someCondition ? ['messages'] : undefined })

// Good — omit the key or always pass an array
useInertiaCable(stream, { ...(someCondition ? { only: ['messages'] } : {}) })
```

### Cache store for server-side debounce

Server-side debounce (`InertiaCable::Debounce`) uses `Rails.cache`. In multi-process deployments (Puma with workers, multiple servers), the default `MemoryStore` is per-process and won't debounce across processes. Use a shared store:

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
```

### Vite HMR stale cache

If hot-module replacement stops working or you see stale behavior after updating `@inertia-cable/react`:

```bash
# Kill Vite dev server, clear cache, restart
rm -rf node_modules/.vite
bin/vite dev
```

### Stream token mismatch

The stream signed in the controller must match the stream the model broadcasts to. If your model broadcasts to `:board` (which resolves to the board's GlobalID) but your controller signs a different object, clients won't receive updates.

```ruby
# Model
broadcasts_to :board  # broadcasts to gid://app/Board/1

# Controller — must sign the same board object
inertia_cable_stream(@post.board)  # signs gid://app/Board/1 ✓
inertia_cable_stream(@post)        # signs gid://app/Post/1 ✗ — wrong stream
```

---

## Requirements

- Ruby >= 3.1
- Rails >= 7.0 (ActionCable, ActiveJob, ActiveSupport)
- Inertia.js >= 1.0 with **React** (`@inertiajs/react`) — the client package is React-only
- ActionCable configured with Redis or SolidCable (production) or async (development)

## Development

```bash
# Ruby specs
bundle install
bundle exec rspec

# Frontend
cd frontend
npm install
npm run build
npm run typecheck
```

## License

MIT
