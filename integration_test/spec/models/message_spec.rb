# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message, type: :model do
  include InertiaCable::TestHelper

  let(:user) { create(:user) }
  let(:chat) { create(:chat) }

  describe "broadcasts_refreshes_to :chat" do
    it "broadcasts a refresh signal when a message is created" do
      assert_broadcasts_on(chat) do
        Message.create!(chat: chat, user: user, body: "Hello!")
      end
    end

    it "broadcasts a refresh signal when a message is updated" do
      message = Message.create!(chat: chat, user: user, body: "Hello!")

      assert_broadcasts_on(chat) do
        message.update!(body: "Updated!")
      end
    end

    it "broadcasts a refresh signal when a message is destroyed" do
      message = Message.create!(chat: chat, user: user, body: "Hello!")

      assert_broadcasts_on(chat) do
        message.destroy!
      end
    end

    it "includes the correct action in the payload" do
      payloads = capture_broadcasts_on(chat) do
        Message.create!(chat: chat, user: user, body: "Hello!")
      end

      expect(payloads.size).to eq(1)
      expect(payloads.first[:type]).to eq("refresh")
      expect(payloads.first[:model]).to eq("Message")
      expect(payloads.first[:action]).to eq("create")
    end

    it "reports destroy action correctly" do
      message = Message.create!(chat: chat, user: user, body: "Hello!")

      payloads = capture_broadcasts_on(chat) do
        message.destroy!
      end

      expect(payloads.first[:action]).to eq("destroy")
    end

    it "does not broadcast when suppressed" do
      assert_no_broadcasts_on(chat) do
        Message.suppressing_broadcasts do
          Message.create!(chat: chat, user: user, body: "Silent")
        end
      end
    end

    it "does not broadcast when globally suppressed" do
      assert_no_broadcasts_on(chat) do
        InertiaCable.suppressing_broadcasts do
          Message.create!(chat: chat, user: user, body: "Silent")
        end
      end
    end
  end
end
