# frozen_string_literal: true

InertiaCable.suppressing_broadcasts do
  user = User.find_or_create_by!(email: "test@example.com") do |u|
    u.name = "Test User"
    u.password = "password1234"
    u.verified = true
  end

  chat = Chat.find_or_create_by!(name: "General")

  if chat.messages.empty?
    chat.messages.create!(body: "Welcome to the chat!", user: user)
    chat.messages.create!(body: "Try opening this in two browser tabs.", user: user)
  end
end
