# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LLM
  module Providers
    class LMStudio
      def initialize(api_url:, model:, timeout_seconds: 600)
        @uri = URI.parse(api_url)
        @model = model
        @timeout_seconds = timeout_seconds
      end

      def generate(prompt:)
        response = http.request(build_request(prompt))
        File.write(File.join(Rails.root, "tmp", "lm_studio_prompt.txt"), prompt, mode: "w")

        raise LLM::Errors::ProviderError, "LM Studio returned HTTP #{response.code} with body #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        normalize_response(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise LLM::Errors::TimeoutError, e.message
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET => e
        raise LLM::Errors::ConnectionError, e.message
      end

      private

      def http
        Net::HTTP.new(@uri.host, @uri.port).tap do |client|
          client.use_ssl = @uri.scheme == "https"
          client.open_timeout = @timeout_seconds
          client.read_timeout = @timeout_seconds
        end
      end

      def build_request(prompt)
        Net::HTTP::Post.new(@uri.request_uri, "Content-Type" => "application/json").tap do |request|
          request.body = {
            model: @model,
            messages: [
              {
                role: "user",
                content: prompt
              }
            ],
            temperature: 0.1,
            stream: false,
            response_format: json_schema_response_format
          }.to_json
        end
      end

      def json_schema_response_format
        {
          type: "json_schema",
          json_schema: {
            name: "tutor_response",
            schema: {
              type: "object",
              properties: {
                default_language: { type: "string" },
                target_language: { type: "string" }
              },
              required: %w[default_language target_language],
              additionalProperties: false
            }
          }
        }
      end

      def normalize_response(body)
        payload = JSON.parse(body)
        content = payload.dig("choices", 0, "message", "content")

        raise LLM::Errors::MalformedResponseError, "LM Studio response missing choices[0].message.content" if content.blank?

        {
          response: content
        }.to_json
      rescue JSON::ParserError, TypeError => e
        raise LLM::Errors::MalformedResponseError, e.message
      end
    end
  end
end
