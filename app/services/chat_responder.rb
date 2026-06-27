# frozen_string_literal: true

require "json"

class ChatResponder
  Result = Struct.new(:user_message, :response_message, :error_message, keyword_init: true) do
    def success?
      response_message&.assistant?
    end
  end

  FALLBACK_DEFAULT_MESSAGE = "I could not parse the model response. Please try again."
  FALLBACK_TARGET_MESSAGE = "Je n'ai pas pu analyser la réponse du modèle. Merci de réessayer."

  def initialize(chat:, client: LLM::Client.new)
    @chat = chat
    @client = client
  end

  def submit_message(content:)
    text = content.to_s.strip
    return Result.new(error_message: "Please enter a message.") if text.blank?

    user_message = chat.messages.create!(
      role: "user",
      content_default_language: text,
      content_target_language: text
    )

    response_message = generate_response_message(messages: conversation_for(user_message), user_message: text)
    Result.new(user_message:, response_message:)
  rescue LLM::Errors::Error => e
    Result.new(user_message:, response_message: build_system_message(friendly_error_message(e)))
  end

  def regenerate_message(message_id:)
    assistant_message = chat.messages.find(message_id)
    raise ArgumentError, "Only assistant messages can be regenerated" unless assistant_message.assistant?

    response_message = regenerate_assistant_message(
      assistant_message,
      messages: conversation_before(assistant_message),
      user_message: last_user_message_for(assistant_message)
    )

    Result.new(response_message:)
  rescue LLM::Errors::Error => e
    Result.new(response_message: build_system_message(friendly_error_message(e)))
  end

  private

  attr_reader :chat, :client

  def generate_response_message(messages:, user_message:)
    raw_response = client.generate(
      prompt: Prompts::Tutor.build(chat:, user_message:, messages:)
    )

    parsed = parse_structured_response(raw_response)
    build_assistant_message(parsed, raw_response:)
  rescue LLM::Errors::MalformedResponseError
    build_assistant_fallback_message(raw_response:)
  end

  def regenerate_assistant_message(assistant_message, messages:, user_message:)
    raw_response = client.generate(
      prompt: Prompts::Tutor.build(chat:, user_message:, messages:)
    )

    parsed = parse_structured_response(raw_response)
    assistant_message.update!(
      content_default_language: parsed.fetch(:default_language),
      content_target_language: parsed.fetch(:target_language),
      raw_response:
    )
    assistant_message
  rescue LLM::Errors::MalformedResponseError
    assistant_message.update!(
      content_default_language: FALLBACK_DEFAULT_MESSAGE,
      content_target_language: FALLBACK_TARGET_MESSAGE,
      raw_response:
    )
    assistant_message
  end

  def parse_structured_response(raw_response)
    outer_payload = JSON.parse(raw_response)
    candidate = outer_payload.is_a?(Hash) ? (outer_payload["response"] || raw_response) : raw_response
    inner_payload = candidate.is_a?(String) ? JSON.parse(candidate) : candidate

    default_language = inner_payload.fetch("default_language").to_s.strip
    target_language = inner_payload.fetch("target_language").to_s.strip

    raise LLM::Errors::MalformedResponseError, "Structured response is missing required content" if default_language.blank? || target_language.blank?

    {
      default_language:,
      target_language:
    }
  rescue JSON::ParserError, KeyError, TypeError => e
    raise LLM::Errors::MalformedResponseError, e.message
  end

  def build_assistant_message(parsed_response, raw_response:)
    chat.messages.create!(
      role: "assistant",
      content_default_language: parsed_response.fetch(:default_language),
      content_target_language: parsed_response.fetch(:target_language),
      raw_response:
    )
  end

  def build_assistant_fallback_message(raw_response:)
    chat.messages.create!(
      role: "assistant",
      content_default_language: FALLBACK_DEFAULT_MESSAGE,
      content_target_language: FALLBACK_TARGET_MESSAGE,
      raw_response:
    )
  end

  def build_system_message(message)
    chat.messages.create!(
      role: "system",
      content_default_language: message,
      content_target_language: message
    )
  end

  def conversation_for(message)
    chat.messages.chronological.select { |item| item.id <= message.id }
  end

  def conversation_before(message)
    chat.messages.chronological.select { |item| item.id < message.id }
  end

  def last_user_message_for(message)
    conversation_before(message).rfind(&:user?)&.content_default_language || ""
  end

  def friendly_error_message(error)
    case error
    when LLM::Errors::ConnectionError
      "Ollama is unavailable. Start Ollama and try again."
    when LLM::Errors::TimeoutError
      "Ollama timed out. Try again with a smaller model or more time."
    else
      "Something went wrong while generating a reply."
    end
  end
end
