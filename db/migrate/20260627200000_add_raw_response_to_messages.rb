# frozen_string_literal: true

class AddRawResponseToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :raw_response, :text
  end
end
