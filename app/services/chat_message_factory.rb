# frozen_string_literal: true

class ChatMessageFactory
  def initialize(chat:)
    @chat = chat
  end

  def user_message(text, prompt_metadata:)
    chat.messages.create!(
      role: "user",
      content_default_language: text,
      content_target_language: text,
      prompt_metadata:
    )
  end

  def streaming_assistant(prompt_metadata:)
    chat.messages.create!(
      role: "assistant",
      content_default_language: ChatResponder::STREAMING_DEFAULT_MESSAGE,
      content_target_language: ChatResponder::STREAMING_TARGET_MESSAGE,
      content_thinking: "",
      raw_response: { response: "" }.to_json,
      generation_status: "generating",
      prompt_metadata:
    )
  end

  def assistant(parsed_response, raw_response:, prompt_metadata:)
    chat.messages.create!(
      role: "assistant",
      content_default_language: parsed_response.fetch(:default_language),
      content_target_language: parsed_response.fetch(:target_language),
      raw_response:,
      prompt_metadata:
    )
  end

  def fallback_assistant(raw_response:, prompt_metadata:)
    chat.messages.create!(
      role: "assistant",
      content_default_language: ChatResponder::FALLBACK_DEFAULT_MESSAGE,
      content_target_language: ChatResponder::FALLBACK_TARGET_MESSAGE,
      raw_response:,
      prompt_metadata:
    )
  end

  def system(message)
    chat.messages.create!(
      role: "system",
      content_default_language: message,
      content_target_language: message
    )
  end

  private

  attr_reader :chat
end
