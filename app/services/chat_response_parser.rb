# frozen_string_literal: true

class ChatResponseParser
  def parse_structured_response(raw_response)
    outer_payload = JSON.parse(raw_response)
    candidate = outer_payload.is_a?(Hash) ? (outer_payload["response"] || raw_response) : raw_response
    inner_payload = candidate.is_a?(String) ? parse_json_object(candidate) : candidate

    default_key = first_present_key(inner_payload, "default_language", "english_language", "default", "english")
    target_key = first_present_key(inner_payload, "target_language", "french_language", "target", "french")
    target_language = inner_payload.fetch(target_key).to_s.strip

    raise LLM::Errors::MalformedResponseError, "Structured response is missing required target_language" if target_language.blank?

    {
      default_language: inner_payload.fetch(default_key).to_s.strip,
      target_language:,
      parse_warnings: parse_warnings(default_key:, target_key:)
    }
  rescue JSON::ParserError, KeyError, TypeError => e
    raise LLM::Errors::MalformedResponseError, e.message
  end

  def split_thinking(text)
    thinking_parts = text.scan(%r{<think>(.*?)</think>}m).flatten
    open_thinking = text[/<think>(.*)\z/m, 1] unless text.include?("</think>")
    thinking = [ *thinking_parts, open_thinking ].compact.join("\n\n").strip
    visible = strip_thinking(text).strip

    [ thinking, visible ]
  end

  def strip_thinking(text)
    text.gsub(%r{<think>.*?</think>}m, "").sub(/<think>.*\z/m, "")
  end

  def streaming_preview_for(text)
    parsed = parse_partial_structured_response(text)
    return parsed if parsed.values.any?(&:present?)

    {
      default_language: visible_streaming_text(text),
      target_language: visible_streaming_text(text)
    }
  end

  def raw_display_content(buffer:, thinking_buffer:, error:)
    content = strip_thinking(buffer.to_s).presence
    return content if content.present?

    thinking = thinking_buffer.to_s.presence
    return "Raw model thinking:\n\n#{thinking}" if thinking.present?

    "Raw model response was empty. Parse error: #{error.message}"
  end

  private

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
    start_index = nil

    text.each_char.with_index do |char, index|
      escaped, in_string = update_string_state(char, escaped, in_string)
      next if escaped || in_string

      start_index, depth = update_json_depth(char, index, start_index, depth)
      return text[start_index..index] if start_index && depth.zero?
    end

    nil
  end

  def update_string_state(char, escaped, in_string)
    return [ false, in_string ] if escaped
    return [ true, in_string ] if in_string && char == "\\"
    return [ false, !in_string ] if char == '"'

    [ false, in_string ]
  end

  def update_json_depth(char, index, start_index, depth)
    if char == "{"
      [ start_index || index, depth + 1 ]
    elsif char == "}" && start_index
      [ start_index, depth - 1 ]
    else
      [ start_index, depth ]
    end
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
end
