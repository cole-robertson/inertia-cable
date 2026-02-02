# frozen_string_literal: true

class CreateChatsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chats do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :messages do |t|
      t.references :chat, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
  end
end
