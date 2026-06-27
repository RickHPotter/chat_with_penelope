# frozen_string_literal: true

class CreateChats < ActiveRecord::Migration[8.1]
  def change
    create_table :chats do |t|
      t.string :title
      t.string :target_language

      t.timestamps
    end
  end
end
