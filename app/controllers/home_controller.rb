# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @chat = Chat.first_or_create!(title: "Cours de Français", target_language: "fr")
    @chat_id = @chat.id
    Rails.logger.info("🗞️ Created chat id: #{@chat_id}")
  end
end
