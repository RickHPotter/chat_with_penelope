# frozen_string_literal: true

class AddStreamingFieldsToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :content_thinking, :text
    add_column :messages, :generation_status, :string, null: false, default: "complete"
  end
end
