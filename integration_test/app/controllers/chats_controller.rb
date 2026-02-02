# frozen_string_literal: true

class ChatsController < InertiaController
  def index
    render inertia: "chats/index", props: {
      chats: Chat.order(:created_at).map { |c|
        { id: c.id, name: c.name, message_count: c.messages.count }
      }
    }
  end

  def show
    chat = Chat.find(params[:id])

    render inertia: "chats/show", props: {
      chat: { id: chat.id, name: chat.name },
      messages: -> {
        chat.messages.includes(:user).order(:created_at).map { |m|
          { id: m.id, body: m.body, user_name: m.user.name, created_at: m.created_at.iso8601 }
        }
      },
      cable_stream: inertia_cable_stream(chat)
    }
  end

  def create
    chat = Chat.create!(name: params[:name])
    redirect_to chat_path(chat)
  end
end
