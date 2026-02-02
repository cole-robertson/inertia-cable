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

## Ruby DSL

### `broadcasts_refreshes_to`

Broadcasts a refresh signal to a named stream whenever the model is created, updated, or destroyed.

```ruby
class Post < ApplicationRecord
  belongs_to :board

  # Stream to the associated record (calls `post.board` to resolve)
  broadcasts_refreshes_to :board

  # Stream to a lambda (receives the record as argument)
  broadcasts_refreshes_to ->(post) { [post.board, :posts] }

  # Stream to a static string
  broadcasts_refreshes_to "global_feed"
end
```

**Stream resolution:**

| Argument | Resolution |
|----------|-----------|
| `:symbol` | Calls the method on the record (`post.board`) |
| `Proc` / `lambda` | Calls with the record (`->(post) { ... }`) |
| `String` | Used as-is |
| ActiveRecord model | Uses GlobalID (`gid://app/Board/1`) |
| `Array` | Joins elements with `:` after resolving each |

**Callback behavior:**

- `after_create_commit` → enqueues `BroadcastJob` (async)
- `after_update_commit` → enqueues `BroadcastJob` (async)
- `after_destroy_commit` → broadcasts synchronously (record is gone, no job needed)

### `broadcasts_refreshes`

Convention-based version that broadcasts to `model_name.plural` (e.g., `"posts"`).

```ruby
class Post < ApplicationRecord
  broadcasts_refreshes                # broadcasts to "posts"
  broadcasts_refreshes "custom_name"  # broadcasts to "custom_name"
end
```

### Instance Methods

You can broadcast manually from anywhere:

```ruby
post = Post.find(1)

# Broadcast to a specific stream
post.broadcast_refresh_to(:board)
post.broadcast_refresh_to("custom_stream")
post.broadcast_refresh_to(->(p) { [p.board, :posts] })

# Broadcast to model_name.plural
post.broadcast_refresh

# Async (via ActiveJob)
post.broadcast_refresh_later_to(:board)
```

### Controller Helper

`inertia_cable_stream` generates a signed token for the stream. Pass it as an Inertia prop.

```ruby
# Single model (uses GlobalID)
inertia_cable_stream(chat)          # => signed token for "gid://app/Chat/1"

# String
inertia_cable_stream("posts")       # => signed token for "posts"

# Array (joined with ":")
inertia_cable_stream([chat, :posts]) # => signed token for "gid://app/Chat/1:posts"
```

The token is verified server-side when the client subscribes, preventing unauthorized access to streams.

## React Hook API

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

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `string[]` | — | Only reload these props |
| `except` | `string[]` | — | Reload all props except these |
| `onRefresh` | `(data) => void` | — | Callback before each reload |
| `debounce` | `number` | `100` | Debounce delay in ms |
| `enabled` | `boolean` | `true` | Enable/disable subscription |

**Refresh payload shape:**

```typescript
interface RefreshPayload {
  type: 'refresh'
  model: string       // e.g. "Message"
  id: number | null   // e.g. 42
  action: string      // "commit"
  timestamp: string   // ISO 8601
}
```

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

// Get or create the shared consumer
const consumer = getConsumer()

// Replace with your own consumer
setConsumer(myCustomConsumer)
```

## Suppressing Broadcasts

Useful for seeds, imports, or bulk operations:

```ruby
InertiaCable.suppressing_broadcasts do
  1000.times { Post.create!(title: "Imported") }
end
# No broadcasts fired
```

## Server-Side Debounce

Coalesce rapid broadcasts at the server level using Rails cache:

```ruby
# In an initializer
InertiaCable.debounce_delay = 0.5  # seconds (default)

# Use debounced broadcast explicitly
InertiaCable::Debounce.broadcast("my_stream", payload)
```

## Configuration

```ruby
# config/initializers/inertia_cable.rb

# Custom signing key (defaults to Rails secret_key_base + "inertia_cable")
InertiaCable.signed_stream_verifier_key = "custom_key"

# Server-side debounce delay
InertiaCable.debounce_delay = 0.5
```

## How It Works

1. **Model saves** → `after_commit` callback fires
2. **BroadcastJob** enqueues (create/update) or broadcasts synchronously (destroy)
3. **ActionCable** broadcasts `{ type: "refresh", model: "Message", id: 42, ... }` to the stream
4. **`useInertiaCable`** hook receives the signal, debounces, then calls `router.reload({ only: ['messages'] })`
5. **Inertia** makes a normal HTTP request to the controller
6. **Controller** re-evaluates lazy props and returns fresh data
7. **React** re-renders with new props

The key insight: no data is sent over the WebSocket. It's purely a notification channel. All data flows through Inertia's existing HTTP request cycle, so your controller remains the single source of truth.

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
