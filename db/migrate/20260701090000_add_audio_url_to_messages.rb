# frozen_string_literal: true

class AddAudioUrlToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :audio_url, :string
  end
end
