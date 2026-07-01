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

  def submit_message_async(content:)
    text = content.to_s.strip
    return Result.new(error_message: "Please enter a message.") if text.blank?

    user_message = chat.messages.create!(
      role: "user",
      content_default_language: text,
      content_target_language: text,
      prompt_metadata: prompt_metadata_for(text)
    )

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
    return stream_say_response_into(assistant_message:, user_message:) if say_command?(user_message)

    prompt = Prompts::Tutor.build(chat:, user_message:, messages: [])
    prompt_metadata = prompt_metadata_for(user_message, prompt:)
    buffer = +""
    thinking_buffer = +""
    content_stream_started = false
    thinking_stream_started = false

    client.generate_stream(prompt:) do |chunk|
      break if cancellation_requested?(assistant_message.id)

      if chunk.is_a?(Hash) && chunk[:type] == :thinking
        text = chunk[:text].to_s
        thinking_buffer << text
        unless thinking_stream_started
          broadcast_stream_update(assistant_message, :thinking_stream, "")
          thinking_stream_started = true
        end
        broadcast_stream_append(assistant_message, :thinking_stream, text)
      else
        text = stream_chunk_text(chunk)
        buffer << text
        unless content_stream_started
          broadcast_stream_update(assistant_message, :target_stream, "")
          broadcast_stream_update(assistant_message, :default_stream, "")
          content_stream_started = true
        end
        broadcast_stream_append(assistant_message, :target_stream, text)
        broadcast_stream_append(assistant_message, :default_stream, text)
      end

      thinking, visible = split_thinking(buffer)
      thinking = [ thinking_buffer, thinking ].compact_blank.join("\n\n")
      preview = streaming_preview_for(visible)

      assistant_message.update!(
        content_default_language: preview.fetch(:default_language).presence || thinking_status(thinking) || STREAMING_DEFAULT_MESSAGE,
        content_target_language: preview.fetch(:target_language).presence || preview.fetch(:default_language).presence || thinking_status(thinking) || STREAMING_TARGET_MESSAGE,
        content_thinking: thinking,
        raw_response: { response: buffer, thinking: thinking_buffer }.to_json,
        prompt_metadata:
      )
    end

    if cancellation_requested?(assistant_message.id)
      assistant_message.update!(
        generation_status: "cancelled",
        raw_response: { response: buffer, thinking: thinking_buffer, cancelled: true }.to_json,
        prompt_metadata: prompt_metadata.merge(output_warnings: [ "generation cancelled" ])
      )
      Rails.cache.delete(cancel_cache_key(assistant_message.id))
      broadcast_message(assistant_message)
      return assistant_message
    end

    parsed = parse_structured_response({ response: strip_thinking(buffer) }.to_json)
    assistant_message.update!(
      content_default_language: parsed.fetch(:default_language),
      content_target_language: parsed.fetch(:target_language),
      content_thinking: [ thinking_buffer, split_thinking(buffer).first ].compact_blank.join("\n\n"),
      generation_status: "complete",
      raw_response: { response: buffer, thinking: thinking_buffer }.to_json,
      prompt_metadata: response_metadata(prompt_metadata, parsed)
    )
    broadcast_message(assistant_message)
    assistant_message
  rescue LLM::Errors::MalformedResponseError => e
    raw_content = raw_display_content(buffer:, thinking_buffer:, error: e)
    assistant_message.update!(
      content_default_language: raw_content,
      content_target_language: raw_content,
      generation_status: "complete",
      raw_response: fallback_raw_response({ response: buffer, thinking: thinking_buffer }.to_json, e),
      prompt_metadata: fallback_metadata(prompt_metadata || assistant_message.prompt_metadata, e)
    )
    broadcast_message(assistant_message)
    assistant_message
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

  private

  attr_reader :chat, :client, :tts_client

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
    chat.messages.create!(
      role: "assistant",
      content_default_language: STREAMING_DEFAULT_MESSAGE,
      content_target_language: STREAMING_TARGET_MESSAGE,
      content_thinking: "",
      raw_response: { response: "" }.to_json,
      generation_status: "generating",
      prompt_metadata: prompt_metadata_for(user_message, prompt:)
    )
  end

  def stream_say_response_into(assistant_message:, user_message:)
    prompt_metadata = prompt_metadata_for(user_message).merge(
      prompt_builder: "TextToSpeech::Client",
      audio_generation: true
    )
    source_text = CommandParser.call(user_message).input.presence || user_message.to_s
    cleaned_text = clean_speech_text(source_text)
    tts_result = tts_client.synthesize(
      input_text: cleaned_text,
      output_basename: "message_#{assistant_message.id}.wav"
    )

    assistant_message.update!(
      content_default_language: "",
      content_target_language: audio_message_content(cleaned_text),
      audio_url: tts_result.audio_url,
      generation_status: "complete",
      raw_response: {
        response: cleaned_text,
        tts: {
          input_text: tts_result.input_text,
          output_path: tts_result.output_path,
          audio_url: tts_result.audio_url,
          response_body: tts_result.response_body
        }
      }.to_json,
      prompt_metadata: prompt_metadata.merge(
        tts_input_text: cleaned_text,
        tts_audio_url: tts_result.audio_url,
        output_warnings: cleanup_warnings(source_text, cleaned_text)
      )
    )
    broadcast_message(assistant_message)
    assistant_message
  rescue TextToSpeech::Error, LLM::Errors::Error => e
    assistant_message.update!(
      content_default_language: "Audio generation failed: #{e.message}",
      content_target_language: "La génération audio a échoué : #{e.message}",
      generation_status: "complete",
      raw_response: { error: e.class.name, message: e.message }.to_json,
      prompt_metadata: prompt_metadata_for(user_message).merge(
        audio_generation: true,
        output_warnings: [ "audio generation failed" ]
      )
    )
    broadcast_message(assistant_message)
    assistant_message
  end

  def clean_speech_text(source_text)
    llm_cleaned_text(source_text).presence || deterministic_speech_cleanup(source_text)
  end

  def llm_cleaned_text(source_text)
    raw_response = client.generate(prompt: speech_cleanup_prompt(source_text))
    parsed = parse_structured_response(raw_response)
    deterministic_speech_cleanup(parsed.fetch(:target_language))
  rescue LLM::Errors::Error
    nil
  end

  def speech_cleanup_prompt(source_text)
    <<~PROMPT
      You clean French text before text-to-speech.

      Return exactly one valid JSON object with:
      {
        "default_language": "",
        "target_language": "cleaned French sentence"
      }

      Rules:
      - Keep the same meaning.
      - Do not translate.
      - Fix apostrophes and obvious spacing only.
      - Use normal apostrophe `'`, never backtick `.
      - Fix common elisions like `Jhabite` to `J'habite` when obvious.
      - Do not add explanations.

      Text:
      #{source_text}
    PROMPT
  end

  def deterministic_speech_cleanup(text)
    cleaned = text.to_s.strip.tr("`´’‘", "'")
    cleaned = cleaned.gsub(/\s+/, " ")
    cleaned = cleaned.gsub(/\b([Jj])(?=ai|aime|adore|arrive|attends|ouvre|habite|emprunte|étais|etais|écoute|ecoute)/, "\\1'")
    cleaned = cleaned.gsub(/\b([CcDdLlMmNnQqSsTt])\s+'/, "\\1'")
    cleaned
  end

  def audio_message_content(cleaned_text)
    <<~TEXT.strip
      # Audio
      #{cleaned_text}
    TEXT
  end

  def cleanup_warnings(source_text, cleaned_text)
    return [] if source_text == cleaned_text

    [ "speech text cleaned before TTS" ]
  end

  def say_command?(text)
    command = CommandParser.call(text)
    command.matched? && command.command == "say"
  end

  def parse_structured_response(raw_response)
    outer_payload = JSON.parse(raw_response)
    candidate = outer_payload.is_a?(Hash) ? (outer_payload["response"] || raw_response) : raw_response
    inner_payload = candidate.is_a?(String) ? parse_json_object(candidate) : candidate

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

  def parse_json_object(candidate)
    JSON.parse(candidate)
  rescue JSON::ParserError
    prefix = first_complete_json_object(candidate)
    raise if prefix.blank?

    JSON.parse(prefix)
  end

  def first_complete_json_object(text)
    depth = 0
    in_string = false
    escaped = false
    started = false
    start_index = nil

    text.each_char.with_index do |char, index|
      if escaped
        escaped = false
        next
      end

      if char == "\\"
        escaped = true if in_string
        next
      end

      if char == '"'
        in_string = !in_string
        next
      end

      next if in_string

      if char == "{"
        start_index ||= index
        started = true
        depth += 1
      elsif char == "}" && started
        depth -= 1
        return text[start_index..index] if depth.zero?
      end
    end

    nil
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

  def broadcast_message(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ message.chat, "messages" ],
      target: ActionView::RecordIdentifier.dom_id(message),
      partial: "chat/message",
      locals: { message: }
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ChatResponder] broadcast failed for message #{message.id}: #{e.class} #{e.message}"
    )
  end

  def broadcast_stream_append(message, target_suffix, text)
    return if text.blank?

    Turbo::StreamsChannel.broadcast_append_to(
      [ message.chat, "messages" ],
      target: ActionView::RecordIdentifier.dom_id(message, target_suffix),
      html: ERB::Util.html_escape(text)
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ChatResponder] stream append failed for message #{message.id}: #{e.class} #{e.message}"
    )
  end

  def broadcast_stream_update(message, target_suffix, html)
    Turbo::StreamsChannel.broadcast_update_to(
      [ message.chat, "messages" ],
      target: ActionView::RecordIdentifier.dom_id(message, target_suffix),
      html:
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ChatResponder] stream update failed for message #{message.id}: #{e.class} #{e.message}"
    )
  end

  def cancel_cache_key(message_id)
    "chat_response_cancel:#{message_id}"
  end

  def cancellation_requested?(message_id)
    Rails.cache.read(cancel_cache_key(message_id)).present?
  end

  def split_thinking(text)
    thinking_parts = text.scan(%r{<think>(.*?)</think>}m).flatten
    open_thinking = text[/<think>(.*)\z/m, 1] unless text.include?("</think>")
    thinking = ([ *thinking_parts, open_thinking ].compact.join("\n\n")).strip
    visible = strip_thinking(text).strip

    [ thinking, visible ]
  end

  def strip_thinking(text)
    text.gsub(%r{<think>.*?</think>}m, "").sub(%r{<think>.*\z}m, "")
  end

  def streaming_preview_for(text)
    parsed = parse_partial_structured_response(text)
    return parsed if parsed.values.any?(&:present?)

    {
      default_language: visible_streaming_text(text),
      target_language: visible_streaming_text(text)
    }
  end

  def parse_partial_structured_response(text)
    parsed = JSON.parse(text)
    return empty_streaming_preview unless parsed.is_a?(Hash)

    {
      default_language: parsed["default_language"].to_s,
      target_language: parsed["target_language"].to_s
    }
  rescue JSON::ParserError, TypeError
    {
      default_language: partial_json_string_value(text, "default_language"),
      target_language: partial_json_string_value(text, "target_language")
    }
  end

  def empty_streaming_preview
    {
      default_language: "",
      target_language: ""
    }
  end

  def partial_json_string_value(text, key)
    match = text.match(/"#{Regexp.escape(key)}"\s*:\s*"(.*)\z/m)
    return "" unless match

    unescape_partial_json_string(match[1])
  end

  def unescape_partial_json_string(value)
    value = value.sub(/\\\z/, "")
    value
      .gsub('\\"', '"')
      .gsub("\\n", "\n")
      .gsub("\\t", "\t")
      .gsub("\\r", "\r")
      .gsub("\\\\", "\\")
  end

  def visible_streaming_text(text)
    text.to_s.presence || "Waiting for first model tokens..."
  end

  def stream_chunk_text(chunk)
    return chunk[:text].to_s if chunk.is_a?(Hash)

    chunk.to_s
  end

  def thinking_status(thinking)
    return if thinking.blank?

    "Model is streaming reasoning only. Waiting for final answer tokens..."
  end

  def raw_display_content(buffer:, thinking_buffer:, error:)
    content = strip_thinking(buffer.to_s).presence
    return content if content.present?

    thinking = thinking_buffer.to_s.presence
    return "Raw model thinking:\n\n#{thinking}" if thinking.present?

    "Raw model response was empty. Parse error: #{error.message}"
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
