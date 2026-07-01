# frozen_string_literal: true

class ChatResponseStreamer
  State = Struct.new(
    :buffer,
    :thinking_buffer,
    :content_stream_started,
    :thinking_stream_started,
    keyword_init: true
  )

  def initialize(responder:, client:)
    @responder = responder
    @client = client
  end

  def call(assistant_message:, user_message:)
    prompt = Prompts::Tutor.build(chat: responder.chat, user_message:, messages: [])
    prompt_metadata = responder.prompt_metadata_for(user_message, prompt:)
    state = State.new(buffer: +"", thinking_buffer: +"")

    stream_chunks(assistant_message, prompt, prompt_metadata, state)
    return cancelled_response(assistant_message, prompt_metadata, state) if responder.cancellation_requested?(assistant_message.id)

    complete_response(assistant_message, prompt_metadata, state)
  rescue LLM::Errors::MalformedResponseError => e
    malformed_response(assistant_message, prompt_metadata, state, e)
  end

  private

  attr_reader :responder, :client

  def stream_chunks(assistant_message, prompt, prompt_metadata, state)
    client.generate_stream(prompt:) do |chunk|
      break if responder.cancellation_requested?(assistant_message.id)

      process_chunk(assistant_message, state, chunk)
      update_preview(assistant_message, prompt_metadata, state)
    end
  end

  def process_chunk(assistant_message, state, chunk)
    if chunk.is_a?(Hash) && chunk[:type] == :thinking
      append_thinking(assistant_message, state, chunk[:text].to_s)
    else
      append_content(assistant_message, state, stream_chunk_text(chunk))
    end
  end

  def append_thinking(assistant_message, state, text)
    state.thinking_buffer << text
    unless state.thinking_stream_started
      responder.broadcast_stream_update(assistant_message, :thinking_stream, "")
      state.thinking_stream_started = true
    end
    responder.broadcast_stream_append(assistant_message, :thinking_stream, text)
  end

  def append_content(assistant_message, state, text)
    state.buffer << text
    unless state.content_stream_started
      responder.broadcast_stream_update(assistant_message, :target_stream, "")
      responder.broadcast_stream_update(assistant_message, :default_stream, "")
      state.content_stream_started = true
    end
    responder.broadcast_stream_append(assistant_message, :target_stream, text)
    responder.broadcast_stream_append(assistant_message, :default_stream, text)
  end

  def update_preview(assistant_message, prompt_metadata, state)
    thinking, visible = responder.split_thinking(state.buffer)
    thinking = [ state.thinking_buffer, thinking ].compact_blank.join("\n\n")
    preview = responder.streaming_preview_for(visible)

    assistant_message.update!(
      content_default_language: preview_default(preview, thinking),
      content_target_language: preview_target(preview, thinking),
      content_thinking: thinking,
      raw_response: raw_response_for(state),
      prompt_metadata:
    )
  end

  def preview_default(preview, thinking)
    preview.fetch(:default_language).presence ||
      responder.thinking_status(thinking) ||
      ChatResponder::STREAMING_DEFAULT_MESSAGE
  end

  def preview_target(preview, thinking)
    preview.fetch(:target_language).presence ||
      preview.fetch(:default_language).presence ||
      responder.thinking_status(thinking) ||
      ChatResponder::STREAMING_TARGET_MESSAGE
  end

  def cancelled_response(assistant_message, prompt_metadata, state)
    assistant_message.update!(
      generation_status: "cancelled",
      raw_response: raw_response_for(state).merge(cancelled: true).to_json,
      prompt_metadata: prompt_metadata.merge(output_warnings: [ "generation cancelled" ])
    )
    Rails.cache.delete(responder.cancel_cache_key(assistant_message.id))
    responder.broadcast_message(assistant_message)
    assistant_message
  end

  def complete_response(assistant_message, prompt_metadata, state)
    parsed = responder.parse_structured_response({ response: responder.strip_thinking(state.buffer) }.to_json)
    assistant_message.update!(
      content_default_language: parsed.fetch(:default_language),
      content_target_language: parsed.fetch(:target_language),
      content_thinking: final_thinking(state),
      generation_status: "complete",
      raw_response: raw_response_for(state),
      prompt_metadata: responder.response_metadata(prompt_metadata, parsed)
    )
    responder.broadcast_message(assistant_message)
    assistant_message
  end

  def malformed_response(assistant_message, prompt_metadata, state, error)
    raw_content = responder.raw_display_content(
      buffer: state.buffer,
      thinking_buffer: state.thinking_buffer,
      error:
    )
    assistant_message.update!(
      content_default_language: raw_content,
      content_target_language: raw_content,
      generation_status: "complete",
      raw_response: responder.fallback_raw_response(raw_response_for(state).to_json, error),
      prompt_metadata: responder.fallback_metadata(prompt_metadata || assistant_message.prompt_metadata, error)
    )
    responder.broadcast_message(assistant_message)
    assistant_message
  end

  def final_thinking(state)
    [ state.thinking_buffer, responder.split_thinking(state.buffer).first ].compact_blank.join("\n\n")
  end

  def raw_response_for(state)
    { response: state.buffer, thinking: state.thinking_buffer }
  end

  def stream_chunk_text(chunk)
    return chunk[:text].to_s if chunk.is_a?(Hash)

    chunk.to_s
  end
end
