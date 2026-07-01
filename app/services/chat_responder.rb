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
  STREAMING_DEFAULT_MESSAGE = "Generating response..."
  STREAMING_TARGET_MESSAGE = "Génération de la réponse..."

  def initialize(chat:, client: LLM::Client.new, tts_client: TextToSpeech::Client.new)
    @chat = chat
    @client = client
    @tts_client = tts_client
  end

  def submit_message(content:)
    text = content.to_s.strip
    return Result.new(error_message: "Please enter a message.") if text.blank?

    user_message = message_factory.user_message(text, prompt_metadata: prompt_metadata_for(text))

    response_message = generate_response_message(user_message: text)
    Result.new(user_message:, response_message:)
  rescue LLM::Errors::Error => e
    Result.new(user_message:, response_message: build_system_message(friendly_error_message(e)))
  end

  def submit_message_async(content:)
    text = content.to_s.strip
    return Result.new(error_message: "Please enter a message.") if text.blank?

    user_message = message_factory.user_message(text, prompt_metadata: prompt_metadata_for(text))

    response_message = build_streaming_assistant_message(user_message: text)
    GenerateAssistantResponseJob.perform_later(response_message.id, text)

    Result.new(user_message:, response_message:)
  end

  def cancel_generation(message_id:)
    message = chat.messages.find(message_id)
    return message unless message.assistant? && (message.generating? || message.cancelling?)

    Rails.cache.write(cancel_cache_key(message.id), true, expires_in: 30.minutes)
    message.update!(
      generation_status: "cancelling",
      prompt_metadata: message.prompt_metadata.merge(output_warnings: [ *message.prompt_metadata["output_warnings"], "cancellation requested" ])
    )
    broadcast_message(message)
    message
  end

  def stream_response_into(assistant_message:, user_message:)
    return audio_responder.call(assistant_message:, user_message:) if say_command?(user_message)

    response_streamer.call(assistant_message:, user_message:)
  end

  def regenerate_message(message_id:)
    assistant_message = chat.messages.find(message_id)
    raise ArgumentError, "Only assistant messages can be regenerated" unless assistant_message.assistant?

    assistant_message.update!(
      content_default_language: STREAMING_DEFAULT_MESSAGE,
      content_target_language: STREAMING_TARGET_MESSAGE,
      content_thinking: "",
      raw_response: { response: "" }.to_json,
      generation_status: "generating",
      prompt_metadata: prompt_metadata_for(last_user_message_for(assistant_message))
    )
    GenerateAssistantResponseJob.perform_later(assistant_message.id, last_user_message_for(assistant_message))

    Result.new(response_message: assistant_message)
  rescue LLM::Errors::Error => e
    Result.new(response_message: build_system_message(friendly_error_message(e)))
  end

  attr_reader :chat, :client, :tts_client

  def parse_structured_response(raw_response)
    response_parser.parse_structured_response(raw_response)
  end

  def build_assistant_message(parsed_response, raw_response:, prompt_metadata:)
    message_factory.assistant(parsed_response, raw_response:, prompt_metadata:)
  end

  def build_assistant_fallback_message(raw_response:, prompt_metadata:)
    message_factory.fallback_assistant(raw_response:, prompt_metadata:)
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

  def broadcast_message(message)
    broadcaster.replace(message)
  end

  def broadcast_stream_append(message, target_suffix, text)
    broadcaster.append_stream(message, target_suffix, text)
  end

  def broadcast_stream_update(message, target_suffix, html)
    broadcaster.update_stream(message, target_suffix, html)
  end

  def cancel_cache_key(message_id)
    "chat_response_cancel:#{message_id}"
  end

  def cancellation_requested?(message_id)
    Rails.cache.read(cancel_cache_key(message_id)).present?
  end

  def split_thinking(text)
    response_parser.split_thinking(text)
  end

  def strip_thinking(text)
    response_parser.strip_thinking(text)
  end

  def streaming_preview_for(text)
    response_parser.streaming_preview_for(text)
  end

  def thinking_status(thinking)
    return if thinking.blank?

    "Model is streaming reasoning only. Waiting for final answer tokens..."
  end

  def raw_display_content(buffer:, thinking_buffer:, error:)
    response_parser.raw_display_content(buffer:, thinking_buffer:, error:)
  end

  def build_system_message(message)
    message_factory.system(message)
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
    metadata_builder.prompt_metadata_for(text, prompt:)
  end

  def response_metadata(prompt_metadata, parsed_response)
    metadata_builder.response_metadata(prompt_metadata, parsed_response)
  end

  private

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

  def build_streaming_assistant_message(user_message:)
    prompt = Prompts::Tutor.build(chat:, user_message:, messages: [])
    message_factory.streaming_assistant(prompt_metadata: prompt_metadata_for(user_message, prompt:))
  end

  def say_command?(text)
    command = CommandParser.call(text)
    command.matched? && command.command == "say"
  end

  def response_streamer
    ChatResponseStreamer.new(responder: self, client:)
  end

  def audio_responder
    ChatAudioResponder.new(responder: self, client:, tts_client:)
  end

  def response_parser
    @response_parser ||= ChatResponseParser.new
  end

  def metadata_builder
    @metadata_builder ||= ChatResponseMetadata.new
  end

  def broadcaster
    @broadcaster ||= ChatMessageBroadcaster.new
  end

  def message_factory
    @message_factory ||= ChatMessageFactory.new(chat:)
  end
end
