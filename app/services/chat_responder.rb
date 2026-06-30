# frozen_string_literal: true

require "json"
require "digest"

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
      content_target_language: text,
      prompt_metadata: prompt_metadata_for(text)
    )

    response_message = generate_response_message(user_message: text)
    Result.new(user_message:, response_message:)
  rescue LLM::Errors::Error => e
    Result.new(user_message:, response_message: build_system_message(friendly_error_message(e)))
  end

  def regenerate_message(message_id:)
    assistant_message = chat.messages.find(message_id)
    raise ArgumentError, "Only assistant messages can be regenerated" unless assistant_message.assistant?

    response_message = regenerate_assistant_message(
      assistant_message,
      user_message: last_user_message_for(assistant_message)
    )

    Result.new(response_message:)
  rescue LLM::Errors::Error => e
    Result.new(response_message: build_system_message(friendly_error_message(e)))
  end

  private

  attr_reader :chat, :client

  def generate_response_message(user_message:)
    prompt = Prompts::Tutor.build(chat:, user_message:, messages: [])
    prompt_metadata = prompt_metadata_for(user_message, prompt:)
    raw_response = client.generate(
      prompt:
    )

    parsed = parse_structured_response(raw_response)
    build_assistant_message(parsed, raw_response:, prompt_metadata: response_metadata(prompt_metadata, parsed))
  rescue LLM::Errors::MalformedResponseError => e
    build_assistant_fallback_message(raw_response: fallback_raw_response(raw_response, e), prompt_metadata: fallback_metadata(prompt_metadata, e))
  end

  def regenerate_assistant_message(assistant_message, user_message:)
    prompt = Prompts::Tutor.build(chat:, user_message:, messages: [])
    prompt_metadata = prompt_metadata_for(user_message, prompt:)
    raw_response = client.generate(
      prompt:
    )

    parsed = parse_structured_response(raw_response)
    assistant_message.update!(
      content_default_language: parsed.fetch(:default_language),
      content_target_language: parsed.fetch(:target_language),
      raw_response:,
      prompt_metadata: response_metadata(prompt_metadata, parsed)
    )
    assistant_message
  rescue LLM::Errors::MalformedResponseError => e
    assistant_message.update!(
      content_default_language: FALLBACK_DEFAULT_MESSAGE,
      content_target_language: FALLBACK_TARGET_MESSAGE,
      raw_response: fallback_raw_response(raw_response, e),
      prompt_metadata: fallback_metadata(prompt_metadata, e)
    )
    assistant_message
  end

  def parse_structured_response(raw_response)
    outer_payload = JSON.parse(raw_response)
    candidate = outer_payload.is_a?(Hash) ? (outer_payload["response"] || raw_response) : raw_response
    inner_payload = candidate.is_a?(String) ? JSON.parse(candidate) : candidate

    default_key = first_present_key(inner_payload, "default_language", "english_language", "default", "english")
    target_key = first_present_key(inner_payload, "target_language", "french_language", "target", "french")

    default_language = inner_payload.fetch(default_key).to_s.strip
    target_language = inner_payload.fetch(target_key).to_s.strip

    raise LLM::Errors::MalformedResponseError, "Structured response is missing required target_language" if target_language.blank?

    {
      default_language:,
      target_language:,
      parse_warnings: parse_warnings(default_key:, target_key:)
    }
  rescue JSON::ParserError, KeyError, TypeError => e
    raise LLM::Errors::MalformedResponseError, e.message
  end

  def first_present_key(payload, *keys)
    keys.find { |key| payload.key?(key) }
  end

  def parse_warnings(default_key:, target_key:)
    warnings = []
    warnings << "used #{default_key} instead of default_language" unless default_key == "default_language"
    warnings << "used #{target_key} instead of target_language" unless target_key == "target_language"
    warnings
  end

  def build_assistant_message(parsed_response, raw_response:, prompt_metadata:)
    chat.messages.create!(
      role: "assistant",
      content_default_language: parsed_response.fetch(:default_language),
      content_target_language: parsed_response.fetch(:target_language),
      raw_response:,
      prompt_metadata:
    )
  end

  def build_assistant_fallback_message(raw_response:, prompt_metadata:)
    chat.messages.create!(
      role: "assistant",
      content_default_language: FALLBACK_DEFAULT_MESSAGE,
      content_target_language: FALLBACK_TARGET_MESSAGE,
      raw_response:,
      prompt_metadata:
    )
  end

  def fallback_raw_response(raw_response, error)
    return raw_response if raw_response.present?

    {
      error: error.class.name,
      message: error.message
    }.to_json
  end

  def fallback_metadata(prompt_metadata, error)
    prompt_metadata.merge(
      parse_warnings: [ error.message ],
      output_warnings: [ "model response could not be parsed" ]
    )
  end

  def build_system_message(message)
    chat.messages.create!(
      role: "system",
      content_default_language: message,
      content_target_language: message
    )
  end

  def conversation_before(message)
    chat.messages.chronological.select { |item| item.id < message.id }
  end

  def last_user_message_for(message)
    conversation_before(message).rfind(&:user?)&.content_default_language || ""
  end

  def friendly_error_message(error)
    chat_provider = Rails.application.config.chat.fetch("chat_provider")

    case error
    when LLM::Errors::ConnectionError
      "#{chat_provider} is unavailable. Start #{chat_provider} and try again."
    when LLM::Errors::TimeoutError
      "#{chat_provider} timed out. Try again with a smaller model or more time."
    else
      "Something went wrong while generating a reply. #{error.message}"
    end
  end

  def prompt_metadata_for(text, prompt: nil)
    classification = MessageClassifier.classify(text)

    metadata = {
      classifier: classification.to_h,
      prompt_builder: prompt_builder_name_for(classification),
      compact_prompt: classification.compact,
      slash_command: classification.command,
      llm_provider: Rails.configuration.chat.fetch("chat_provider"),
      llm_model: Rails.configuration.chat.fetch("chat_model")
    }

    if prompt
      metadata[:prompt_digest] = Digest::SHA256.hexdigest(prompt)
      metadata[:prompt_preview] = prompt.first(2_000)
    end

    metadata
  end

  def prompt_builder_name_for(classification)
    if classification.compact
      return {
        "validate" => "Prompts::Compact::Validate",
        "check" => "Prompts::Compact::Validate",
        "correct" => "Prompts::Compact::Validate",
        "define" => "Prompts::Compact::Define",
        "explain" => "Prompts::Compact::Explain",
        "translate" => "Prompts::Compact::Translate",
        "say" => "Prompts::Compact::Say"
      }.fetch(classification.command, "Prompts::Compact")
    end

    {
      french_sentence: "Prompts::FrenchSentence",
      english_sentence: "Prompts::EnglishSentence",
      vocabulary: "Prompts::Vocabulary",
      grammar: "Prompts::Grammar",
      translation: "Prompts::Translation",
      conversation: "Prompts::Tutor legacy fallback"
    }.fetch(classification.intent)
  end

  def response_metadata(prompt_metadata, parsed_response)
    prompt_metadata.merge(
      parse_warnings: parsed_response.fetch(:parse_warnings),
      output_warnings: output_warnings_for(parsed_response)
    )
  end

  def output_warnings_for(parsed_response)
    warnings = []
    default_language = parsed_response.fetch(:default_language)
    target_language = parsed_response.fetch(:target_language)

    warnings << "target_language contains D'umas" if target_language.match?(/D'umas/i)
    warnings << "target_language contains same-language glosses" if target_language.match?(/\b(\p{L}+)\s*\(\1\)/i)
    warnings << "target_language contains same-language arrows" if target_language.match?(/([\p{L}'’ ]{3,})\s*→\s*\1/i)
    warnings << "default_language repeats translation explanation" if repeated_translation_explanation?(default_language)
    warnings << "response contains duplicate alternatives" if [ default_language, target_language ].any? { |content| duplicate_alternative?(content) }
    warnings << "response contains literal language names instead of answers" if default_language == "English" && target_language == "French"

    warnings
  end

  def duplicate_alternative?(content)
    content.scan(/['«"]([^'»"]+)['»"]\s+or\s+['«"]\1['»"]/i).any?
  end

  def repeated_translation_explanation?(content)
    translation = content[/Translation:\s*(.+)/i, 1]
    explanation = content[/Translation explanation:\s*(.+)/i, 1]

    translation.present? && explanation.present? && translation.strip == explanation.strip
  end
end
