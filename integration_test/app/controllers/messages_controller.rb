# frozen_string_literal: true

class MessagesController < InertiaController
  def create
    chat = Chat.find(params[:chat_id])
    chat.messages.create!(body: params[:body], user: Current.user)

    redirect_to chat_path(chat)
  end

  def destroy
    message = Message.find(params[:id])
    chat = message.chat
    message.destroy!

    redirect_to chat_path(chat)
  end
end
