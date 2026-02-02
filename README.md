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
  broadcasts_refreshes_to :chat
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

### `broadcasts_refreshes_to`

Broadcasts a refresh signal to a named stream whenever the model is committed. Uses a single `after_commit` callback.

```ruby
class Post < ApplicationRecord
  belongs_to :board

  # Stream to the associated record (calls post.board to resolve)
  broadcasts_refreshes_to :board

  # Stream to a lambda (receives the record as argument)
  broadcasts_refreshes_to ->(post) { [post.board, :posts] }

  # Stream to a static string
  broadcasts_refreshes_to "global_feed"
end
```

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
  broadcasts_refreshes_to :board, on: [:create, :destroy]
end
```

#### `if:` / `unless:` — conditional broadcasts

Standard Rails callback conditions:

```ruby
class Post < ApplicationRecord
  # Only broadcast published posts
  broadcasts_refreshes_to :board, if: :published?

  # Skip draft posts
  broadcasts_refreshes_to :board, unless: -> { draft? }
end
```

All options compose:

```ruby
class Post < ApplicationRecord
  broadcasts_refreshes_to :board, on: [:create, :destroy], if: :published?
end
```

### `broadcasts_refreshes`

Convention-based version that broadcasts to `model_name.plural` (e.g., `"posts"`):

```ruby
class Post < ApplicationRecord
  broadcasts_refreshes                           # broadcasts to "posts"
  broadcasts_refreshes on: [:create, :destroy]   # with options
end
```

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
```

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

---

## React Hook

### `useInertiaCable(signedStreamName, options?)`

```tsx
useInertiaCable(cable_stream, {
  // Only reload these props (passed to router.reload)
  only: ['messages'],

  // Reload all props except these
  except: ['metadata'],

  // Callback fired on every refresh signal (before reload)
  onRefresh: (data) => {
    console.log(`${data.model} #${data.id} was ${data.action}`)
  },

  // Client-side debounce in ms (default: 100)
  // Coalesces rapid signals into a single reload
  debounce: 200,

  // Disable/enable the subscription (default: true)
  enabled: isVisible,
})
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `string[]` | — | Only reload these props |
| `except` | `string[]` | — | Reload all props except these |
| `onRefresh` | `(data) => void` | — | Callback before each reload |
| `debounce` | `number` | `100` | Debounce delay in ms |
| `enabled` | `boolean` | `true` | Enable/disable subscription |

### `InertiaCableProvider`

Optional context provider for a custom ActionCable URL (default is `/cable`):

```tsx
import { InertiaCableProvider } from '@inertia-cable/react'

function App({ children }) {
  return (
    <InertiaCableProvider url="wss://cable.example.com/cable">
      {children}
    </InertiaCableProvider>
  )
}
```

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

Coalesce rapid broadcasts using Rails cache:

```ruby
InertiaCable.debounce_delay = 0.5  # seconds (default)

# Use debounced broadcast explicitly
InertiaCable::Debounce.broadcast("my_stream", payload)
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

## Requirements

- Ruby >= 3.1
- Rails >= 7.0 (ActionCable, ActiveJob, ActiveSupport)
- Inertia.js >= 1.0 (React adapter)
- ActionCable configured with Redis (production) or async (development)

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
