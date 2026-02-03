# InertiaCable

ActionCable broadcast DSL for [Inertia.js](https://inertiajs.com/) Rails applications. Three lines of code to get real-time updates.

InertiaCable broadcasts lightweight JSON signals over ActionCable. The client receives them and calls `router.reload()` to re-fetch props through Inertia's normal HTTP flow — your controller stays the single source of truth. For ephemeral data like job progress or notifications, [direct messages](#direct-messages) stream data over the WebSocket without triggering a reload.

```
Model save → after_commit → ActionCable broadcast (signal)
                                    ↓
React hook subscribes → receives signal → router.reload({ only: ['messages'] })
                                    ↓
Inertia HTTP request → controller re-evaluates props → React re-renders
```

> **Coming from Turbo Streams?** `broadcasts_to` replaces `broadcasts_refreshes_to`, and `broadcast_message_to` covers use cases where you'd reach for `broadcast_append_to` or `broadcast_replace_to` — but without HTML partials, since Inertia reloads props from your controller instead.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Model DSL](#model-dsl)
- [Controller Helper](#controller-helper)
- [React Hook](#react-hook)
- [Direct Messages](#direct-messages)
- [Suppressing Broadcasts](#suppressing-broadcasts)
- [Server-Side Debounce](#server-side-debounce)
- [Testing](#testing)
- [Configuration](#configuration)
- [Security](#security)
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

Optionally run the install generator:

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

Broadcasts a refresh signal to a named stream whenever the model is committed (via a single `after_commit` callback).

```ruby
class Post < ApplicationRecord
  belongs_to :board

  broadcasts_to :board                                  # stream to associated record
  broadcasts_to ->(post) { [post.board, :posts] }       # stream to a lambda
  broadcasts_to "global_feed"                           # stream to a static string
end
```

`broadcasts_refreshes_to` is available as a legacy alias.

#### Stream resolution

| Argument | Resolves to |
|----------|-------------|
| `:symbol` | Calls the method on the record (`post.board`) |
| `Proc` / `lambda` | Calls with the record (`->(post) { ... }`) |
| `String` | Used as-is |
| ActiveRecord model | GlobalID (`gid://app/Board/1`) |
| `Array` | Joins elements with `:` after resolving each |

#### Options

```ruby
class Post < ApplicationRecord
  # on: — limit which events trigger broadcasts (default: all)
  broadcasts_to :board, on: [:create, :destroy]

  # if: / unless: — standard Rails callback conditions
  broadcasts_to :board, if: :published?
  broadcasts_to :board, unless: -> { draft? }

  # extra: — attach custom data to the payload (Hash or Proc)
  broadcasts_to :board, extra: { priority: "high" }
  broadcasts_to :board, extra: ->(post) { { category: post.category } }

  # debounce: — coalesce rapid broadcasts server-side (requires shared cache store)
  broadcasts_to :board, debounce: true        # uses global InertiaCable.debounce_delay
  broadcasts_to :board, debounce: 1.0         # custom delay in seconds

  # Options compose
  broadcasts_to :board, on: [:create, :destroy], if: :published?
end
```

### `broadcasts`

Convention-based version that broadcasts to `model_name.plural` (e.g., `"posts"`):

```ruby
class Post < ApplicationRecord
  broadcasts                           # broadcasts to "posts"
  broadcasts on: [:create, :destroy]   # with options
end
```

`broadcasts_refreshes` is available as a legacy alias.

### Instance methods

```ruby
post = Post.find(1)

# Sync
post.broadcast_refresh_to(board)
post.broadcast_refresh_to(board, :posts)       # compound stream
post.broadcast_refresh                         # to model_name.plural

# Async (via ActiveJob)
post.broadcast_refresh_later_to(board)
post.broadcast_refresh_later

# With extra payload or debounce
post.broadcast_refresh_to(board, extra: { priority: "high" })
post.broadcast_refresh_later_to(board, debounce: 2.0)

# With inline condition (block — skips broadcast if falsy)
post.broadcast_refresh_to(board) { published? }

# Direct messages (ephemeral data, no prop reload)
post.broadcast_message_to(board, data: { progress: 50 })
post.broadcast_message_later_to(board, data: { progress: 50 })
post.broadcast_message_to(board, data: { progress: 50 }) { running? }
```

### Broadcast payload

Refresh broadcasts send this JSON:

```json
{
  "type": "refresh",
  "model": "Message",
  "id": 42,
  "action": "create",
  "timestamp": "2026-02-02T18:15:19+00:00",
  "extra": {}
}
```

The `action` field is `"create"`, `"update"`, or `"destroy"`. The `extra` field contains data from the `extra:` option (empty object if not set).

Message broadcasts send a minimal payload:

```json
{
  "type": "message",
  "data": { "progress": 50, "total": 200 }
}
```

Messages are ephemeral — no `model`, `id`, `action`, or `timestamp` fields.

---

## Controller Helper

`inertia_cable_stream` generates a cryptographically signed stream token. Pass it as an Inertia prop.

```ruby
inertia_cable_stream(chat)                # signed "gid://app/Chat/1"
inertia_cable_stream("posts")             # signed "posts"
inertia_cable_stream(chat, :messages)     # signed "gid://app/Chat/1:messages"
```

Each element is resolved individually: objects that respond to `to_gid_param` use GlobalID, otherwise `to_param` is called. Nested arrays are flattened and `nil`/blank elements are stripped.

The token is verified server-side when the client subscribes — invalid or tampered tokens are rejected.

---

## React Hook

> Only the React adapter (`@inertia-cable/react`) is available. Vue and Svelte adapters are welcome as community contributions.

### `useInertiaCable(signedStreamName, options?)`

Returns `{ connected }` — a boolean indicating whether the WebSocket subscription is active.

```tsx
const { connected } = useInertiaCable(cable_stream, {
  only: ['messages'],           // only reload these props
  except: ['metadata'],         // reload all except these
  onRefresh: (data) => {        // callback before each reload
    console.log(`${data.model} #${data.id} was ${data.action}`)
    if (data.extra?.priority === 'high') toast.warn('Priority update!')
  },
  onMessage: (data) => {        // receive direct messages (no reload)
    setProgress(data.progress)
  },
  onConnected: () => {},        // subscription connected
  onDisconnected: () => {},     // connection dropped
  debounce: 200,                // client-side debounce in ms (default: 100)
  enabled: isVisible,           // disable/enable subscription (default: true)
})
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `string[]` | — | Only reload these props |
| `except` | `string[]` | — | Reload all props except these |
| `onRefresh` | `(data) => void` | — | Callback before each reload |
| `onMessage` | `(data) => void` | — | Receive direct message data (no reload) |
| `onConnected` | `() => void` | — | Called when subscription connects |
| `onDisconnected` | `() => void` | — | Called when connection drops |
| `debounce` | `number` | `100` | Debounce delay in ms |
| `enabled` | `boolean` | `true` | Enable/disable subscription |

**Automatic catch-up on reconnection:** When a WebSocket connection drops and reconnects (e.g., network interruption or backgrounded tab), the hook automatically triggers a `router.reload()` to fetch any changes missed while disconnected. This only fires on *re*connection — not the initial connect. ActionCable handles the reconnection itself (with exponential backoff); the hook just ensures your props are fresh when it comes back.

Use `connected` to show connection state in the UI:

```tsx
const { connected } = useInertiaCable(cable_stream, { only: ['messages'] })

if (!connected) return <Banner>Reconnecting…</Banner>
```

### Multiple streams on one page

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

### `InertiaCableProvider`

Optional context provider for a custom ActionCable URL. Without it, the hook connects to the default `/cable` endpoint.

```tsx
import { InertiaCableProvider } from '@inertia-cable/react'

createInertiaApp({
  setup({ el, App, props }) {
    createRoot(el).render(
      <InertiaCableProvider url="wss://cable.example.com/cable">
        <App {...props} />
      </InertiaCableProvider>
    )
  },
})
```

`getConsumer()` and `setConsumer()` are also exported for low-level access to the ActionCable consumer singleton.

TypeScript types (`RefreshPayload`, `MessagePayload`, `CablePayload`, `UseInertiaCableOptions`, `UseInertiaCableReturn`, `InertiaCableProviderProps`) are exported from `@inertia-cable/react`. `CablePayload` is a discriminated union of `RefreshPayload | MessagePayload` for type-safe handling of raw payloads.

---

## Direct Messages

Push ephemeral data directly into React state over the same signed stream — no prop reload, no extra hook.

### Job progress example

```ruby
# app/jobs/csv_import_job.rb
class CsvImportJob < ApplicationJob
  def perform(import)
    rows = CSV.read(import.file.path)
    rows.each_with_index do |row, i|
      process_row(row)
      import.broadcast_message_to(import.user, data: { progress: i + 1, total: rows.size })
    end
    import.broadcast_refresh_to(import.user) # final reload with completed data
  end
end
```

```tsx
import { useState } from 'react'
import { useInertiaCable } from '@inertia-cable/react'

export default function ImportShow({ import_record, cable_stream }) {
  const [progress, setProgress] = useState<{ progress: number; total: number } | null>(null)

  useInertiaCable(cable_stream, {
    only: ['import_record'],
    onMessage: (data) => setProgress({ progress: data.progress as number, total: data.total as number }),
  })

  return (
    <div>
      <h1>Import #{import_record.id}</h1>
      {progress && <p>Processing {progress.progress} / {progress.total}</p>}
    </div>
  )
}
```

### Usage patterns

```tsx
// Prop reload only (unchanged)
useInertiaCable(stream, { only: ['messages'] })

// Direct data only (no reload)
useInertiaCable(stream, {
  onMessage: (data) => setProgress(data.progress)
})

// Both — progress during job, final reload on completion
useInertiaCable(stream, {
  only: ['imports'],
  onMessage: (data) => setProgress(data.progress)
})
```

Messages are delivered immediately with no debouncing. Each `broadcast_message_to` call triggers exactly one `onMessage` callback.

---

## Suppressing Broadcasts

Thread-safe and nestable:

```ruby
# Global — suppress all models
InertiaCable.suppressing_broadcasts do
  1000.times { Post.create!(title: "Imported") }
end

# Class-level
Post.suppressing_broadcasts do
  Post.create!(title: "Silent")
end
```

---

## Server-Side Debounce

Optionally coalesce rapid broadcasts using Rails cache. **Not used by default** — the client-side 100ms debounce handles most cases.

Requires a shared cache store (Redis, Memcached, or SolidCache) in multi-process deployments.

```ruby
InertiaCable.debounce_delay = 0.5  # seconds (default)

InertiaCable::Debounce.broadcast("my_stream", payload)
InertiaCable::Debounce.broadcast("my_stream", payload, delay: 2.0)
```

---

## Testing

InertiaCable ships a `TestHelper` module:

```ruby
class MessageTest < ActiveSupport::TestCase
  include InertiaCable::TestHelper

  test "broadcasting on create" do
    chat = chats(:general)

    assert_broadcasts_on(chat) do
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
  end
end
```

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
InertiaCable.signed_stream_verifier_key = "custom_key"  # default: secret_key_base + "inertia_cable"
InertiaCable.debounce_delay = 0.5                        # server-side debounce (seconds)
```

---

## Security

Stream tokens are HMAC-SHA256 signed using `secret_key_base` and verified server-side on subscription. Invalid tokens are rejected. No data travels over the WebSocket — actual data is fetched via Inertia's normal HTTP cycle, which runs through your controller and its authorization logic on every reload. Token rotation follows `secret_key_base` rotation.

---

## Troubleshooting

### Stream token mismatch

The stream signed in the controller must match what the model broadcasts to:

```ruby
# Model
broadcasts_to :board  # broadcasts to gid://app/Board/1

# Controller — must sign the same object
inertia_cable_stream(@post.board)  # ✓ signs gid://app/Board/1
inertia_cable_stream(@post)        # ✗ signs gid://app/Post/1
```

### `only`/`except` crashes

Always pass arrays, never `undefined`:

```tsx
// Bad
useInertiaCable(stream, { only: someCondition ? ['messages'] : undefined })

// Good
useInertiaCable(stream, { ...(someCondition ? { only: ['messages'] } : {}) })
```

### Server-side debounce not working across processes

`Rails.cache` defaults to `MemoryStore` (per-process). Use a shared store in production:

```ruby
config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
```

---

## Requirements

- Ruby >= 3.1
- Rails >= 7.0 (ActionCable, ActiveJob, ActiveSupport)
- Inertia.js >= 1.0 with React (`@inertiajs/react`)
- ActionCable configured with Redis or SolidCable (production) or async (development)

## Development

```bash
bundle install && bundle exec rspec     # Ruby specs
cd frontend && npm install && npm test  # Frontend
```

## License

MIT
