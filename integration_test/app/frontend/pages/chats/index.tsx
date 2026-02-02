import { Head, Link, useForm } from "@inertiajs/react"
import AppLayout from "@/layouts/app-layout"

interface Chat {
  id: number
  name: string
  message_count: number
}

export default function ChatsIndex({ chats }: { chats: Chat[] }) {
  const form = useForm({ name: "" })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    form.post("/chats", { onSuccess: () => form.reset() })
  }

  return (
    <AppLayout breadcrumbs={[{ title: "Chats", href: "/chats" }]}>
      <Head title="Chats" />

      <div className="mx-auto max-w-2xl p-8">
        <h1 className="text-2xl font-bold mb-6">Chats</h1>

        <form onSubmit={handleSubmit} className="flex gap-2 mb-8">
          <input
            type="text"
            value={form.data.name}
            onChange={(e) => form.setData("name", e.target.value)}
            placeholder="New chat name..."
            className="flex-1 rounded-lg border border-gray-300 px-4 py-2 dark:border-gray-600 dark:bg-gray-800"
          />
          <button
            type="submit"
            disabled={form.processing}
            className="rounded-lg bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 disabled:opacity-50"
          >
            Create
          </button>
        </form>

        <div className="space-y-2">
          {chats.map((chat) => (
            <Link
              key={chat.id}
              href={`/chats/${chat.id}`}
              className="block rounded-lg border border-gray-200 p-4 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800"
            >
              <div className="font-medium">{chat.name}</div>
              <div className="text-sm text-gray-500">{chat.message_count} messages</div>
            </Link>
          ))}
          {chats.length === 0 && (
            <p className="text-gray-500">No chats yet. Create one above.</p>
          )}
        </div>
      </div>
    </AppLayout>
  )
}
