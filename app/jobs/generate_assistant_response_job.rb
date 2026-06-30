# frozen_string_literal: true

class GenerateAssistantResponseJob < ApplicationJob
  queue_as :default

  def perform(message_id, user_message)
    assistant_message = Message.find(message_id)

    ChatResponder.new(chat: assistant_message.chat).stream_response_into(
      assistant_message:,
      user_message:
    )
  end
end
