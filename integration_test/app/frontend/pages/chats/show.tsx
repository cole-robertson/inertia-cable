import { Head, useForm } from "@inertiajs/react"
import { useInertiaCable } from "@/lib/inertia-cable"
import AppLayout from "@/layouts/app-layout"

interface Message {
  id: number
  body: string
  user_name: string
  created_at: string
}

interface Props {
  chat: { id: number; name: string }
  messages: Message[]
  cable_stream: string
}

export default function ChatShow({ chat, messages, cable_stream }: Props) {
  const { connected } = useInertiaCable(cable_stream, { only: ["messages"] })

  const form = useForm({ body: "" })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    form.post(`/chats/${chat.id}/messages`, {
      onSuccess: () => form.reset(),
      preserveScroll: true,
    })
  }

  return (
    <AppLayout breadcrumbs={[{ title: "Chats", href: "/chats" }, { title: chat.name, href: `/chats/${chat.id}` }]}>
      <Head title={chat.name} />

      <div className="mx-auto flex max-w-2xl flex-col p-8" style={{ height: "calc(100vh - 120px)" }}>
        <h1 className="text-2xl font-bold mb-4">{chat.name}</h1>

        <div className="mb-2 flex items-center gap-2 text-xs text-gray-400">
          <span className={`inline-block h-2 w-2 rounded-full ${connected ? "bg-green-500" : "bg-yellow-500 animate-pulse"}`} />
          {connected ? "Connected" : "Reconnecting…"}
          <span className="ml-2">— open this page in two tabs to test</span>
        </div>

        <div className="flex-1 overflow-y-auto space-y-3 mb-4 rounded-lg border border-gray-200 p-4 dark:border-gray-700">
          {messages.map((msg) => (
            <div key={msg.id} className="rounded-lg bg-gray-50 p-3 dark:bg-gray-800">
              <div className="flex items-baseline justify-between">
                <span className="font-medium text-sm">{msg.user_name}</span>
                <span className="text-xs text-gray-400">
                  {new Date(msg.created_at).toLocaleTimeString()}
                </span>
              </div>
              <p className="mt-1">{msg.body}</p>
            </div>
          ))}
          {messages.length === 0 && (
            <p className="text-gray-500 text-center py-8">No messages yet. Say something!</p>
          )}
        </div>

        <form onSubmit={handleSubmit} className="flex gap-2">
          <input
            type="text"
            value={form.data.body}
            onChange={(e) => form.setData("body", e.target.value)}
            placeholder="Type a message..."
            className="flex-1 rounded-lg border border-gray-300 px-4 py-2 dark:border-gray-600 dark:bg-gray-800"
            autoFocus
          />
          <button
            type="submit"
            disabled={form.processing || !form.data.body.trim()}
            className="rounded-lg bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 disabled:opacity-50"
          >
            Send
          </button>
        </form>
      </div>
    </AppLayout>
  )
}
