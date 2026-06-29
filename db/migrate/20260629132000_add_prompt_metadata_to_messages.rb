# frozen_string_literal: true

class AddPromptMetadataToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :prompt_metadata, :jsonb, null: false, default: {}
  end
end
