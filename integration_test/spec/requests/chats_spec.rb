# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chats", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /chats" do
    it "returns the chats index page" do
      create(:chat, name: "General")

      get "/chats"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /chats/:id" do
    it "returns the chat show page with a cable_stream prop" do
      chat = create(:chat, name: "General")
      create(:message, chat: chat, user: user, body: "Hello!")

      get "/chats/#{chat.id}"

      expect(response).to have_http_status(:ok)

      # Verify the Inertia response includes our cable_stream prop
      # by checking the response body contains a signed stream token
      expect(response.body).to include("cable_stream")
    end
  end

  describe "POST /chats/:id/messages" do
    it "creates a message and redirects back" do
      chat = create(:chat, name: "General")

      expect {
        post "/chats/#{chat.id}/messages", params: { body: "New message" }
      }.to change(Message, :count).by(1)

      expect(response).to redirect_to(chat_path(chat))
    end
  end
end
