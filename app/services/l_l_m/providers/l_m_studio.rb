# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LLM
  module Providers
    class LMStudio
      def initialize(api_url:, model:, timeout_seconds: 600)
        @uri = responses_uri_for(api_url)
        @model = model
        @timeout_seconds = timeout_seconds
      end

      def generate(prompt:)
        request = build_request(prompt)
        write_debug_request_payload(request)
        response = http.request(request)
        File.write(File.join(Rails.root, "tmp", "lm_studio_prompt.txt"), prompt, mode: "w")

        raise LLM::Errors::ProviderError, "LM Studio returned HTTP #{response.code} with body #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        normalize_response(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise LLM::Errors::TimeoutError, e.message
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET => e
        raise LLM::Errors::ConnectionError, e.message
      end

      def generate_stream(prompt:, &)
        request = build_request(prompt, stream: true)
        write_debug_request_payload(request)
        stream_buffer = +""
        @stream_debug_events_logged = 0

        http.request(request) do |response|
          raise LLM::Errors::ProviderError, "LM Studio returned HTTP #{response.code} with body #{response.body}" unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            Rails.logger.debug("[LMStudio] stream chunk bytes=#{chunk.to_s.bytesize}")
            stream_buffer << chunk.to_s

            each_stream_event(stream_buffer) do |event|
              parse_stream_event(event, &)
            end
          end

          parse_stream_event(stream_buffer, &) if stream_buffer.present?
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise LLM::Errors::TimeoutError, e.message
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET => e
        raise LLM::Errors::ConnectionError, e.message
      end

      private

      def each_stream_event(buffer)
        loop do
          separator_index = buffer.index(/\r?\n\r?\n/)
          break unless separator_index

          separator = buffer[separator_index, buffer[separator_index, 4].start_with?("\r\n\r\n") ? 4 : 2]
          event = buffer.slice!(0, separator_index + separator.length)
          yield event
        end
      end

      def parse_stream_event(event)
        event_data_lines(event).each do |data|
          payload = JSON.parse(data)
          log_stream_payload_shape(payload)
          content = stream_content_from(payload)
          yield content if content.present?
        rescue JSON::ParserError
          Rails.logger.debug("[LMStudio] Ignoring malformed stream event: #{data.inspect}")
          next
        end
      end

      def event_data_lines(event)
        event.to_s.each_line.filter_map do |line|
          next unless line.start_with?("data:")

          data = line.delete_prefix("data:").strip
          next if data.blank? || data == "[DONE]"

          data
        end
      end

      def stream_content_from(payload)
        responses_content = responses_stream_content_from(payload)
        return responses_content if responses_content.present?

        choice = payload.dig("choices", 0) || {}
        delta = choice["delta"] || {}
        message = choice["message"] || {}

        content = first_string(delta["content"], message["content"], payload["response"], payload["content"], payload["text"])
        return { type: :content, text: content } if content.present?

        reasoning = delta["reasoning_content"] || delta["reasoning"] || delta["thinking"] ||
                    message["reasoning_content"] || message["reasoning"] || message["thinking"]
        return { type: :thinking, text: reasoning } unless reasoning.nil?

        nil
      end

      def responses_stream_content_from(payload)
        type = payload["type"].to_s
        delta = payload["delta"] || payload["text_delta"] || payload["content_delta"]
        text = payload["text"] || payload["output_text"]

        if type.include?("reasoning")
          reasoning = delta || text || payload["summary_text"]
          return { type: :thinking, text: reasoning } unless reasoning.nil?
        end

        return { type: :content, text: delta } if type == "response.output_text.delta" && delta.present?

        nil
      end

      def first_string(*values)
        values.find { |value| value.is_a?(String) && value.present? }
      end

      def log_stream_payload_shape(payload)
        return if @stream_debug_events_logged.to_i >= 5

        choice = payload.dig("choices", 0) || {}
        delta = choice["delta"] || {}
        message = choice["message"] || {}
        Rails.logger.debug(
          "[LMStudio] stream payload keys=#{payload.keys.inspect} " \
          "choice_keys=#{choice.keys.inspect} delta_keys=#{delta.keys.inspect} " \
          "message_keys=#{message.keys.inspect} finish_reason=#{choice['finish_reason'].inspect}"
        )
        if delta["content"] || choice["finish_reason"]
          Rails.logger.debug("[LMStudio] find-me")
          Rails.logger.info(payload)
          Rails.logger.debug("[LMStudio] find-me")
        end
        @stream_debug_events_logged = @stream_debug_events_logged.to_i + 1
      end

      def parse_stream_chunk(chunk, &)
        buffer = +chunk.to_s

        each_stream_event(buffer) do |event|
          parse_stream_event(event, &)
        end
      end

      def http
        Net::HTTP.new(@uri.host, @uri.port).tap do |client|
          client.use_ssl = @uri.scheme == "https"
          client.open_timeout = @timeout_seconds
          client.read_timeout = @timeout_seconds
        end
      end

      def build_request(prompt, stream: false)
        Net::HTTP::Post.new(@uri.request_uri, request_headers(stream:)).tap do |request|
          request.body = {
            model: @model,
            input: prompt,
            reasoning: { effort: "none" },
            max_output_tokens: max_tokens,
            stream:
          }.to_json
        end
      end

      def responses_uri_for(api_url)
        uri = URI.parse(api_url)
        uri.path = uri.path.sub(%r{/v1/chat/completions\z}, "/v1/responses")
        uri
      end

      def write_debug_request_payload(request)
        return unless Rails.env.development? || Rails.env.test?

        File.write(
          Rails.root.join("tmp", "lm_studio_request_payload.json"),
          JSON.pretty_generate(JSON.parse(request.body))
        )
      rescue JSON::ParserError
        File.write(Rails.root.join("tmp", "lm_studio_request_payload.json"), request.body.to_s)
      end

      def request_headers(stream:)
        headers = {
          "Content-Type" => "application/json"
        }

        if stream
          headers["Accept"] = "text/event-stream"
          headers["Cache-Control"] = "no-cache"
        end

        headers
      end

      def max_tokens
        ENV.fetch("CHAT_MAX_TOKENS", "3000").to_i
      end

      def normalize_response(body)
        payload = JSON.parse(body)
        content = responses_response_content(payload) || payload.dig("choices", 0, "message", "content")

        raise LLM::Errors::MalformedResponseError, "LM Studio response missing output text" if content.blank?

        {
          response: content
        }.to_json
      rescue JSON::ParserError, TypeError => e
        raise LLM::Errors::MalformedResponseError, e.message
      end

      def responses_response_content(payload)
        return payload["output_text"] if payload["output_text"].present?

        Array(payload["output"]).filter_map do |item|
          Array(item["content"]).filter_map do |content|
            content["text"] || content.dig("text", "value")
          end.join
        end.join.presence
      end
    end
  end
end
