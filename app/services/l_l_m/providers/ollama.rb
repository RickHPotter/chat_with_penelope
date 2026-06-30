# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LLM
  module Providers
    class Ollama
      def initialize(api_url:, model:, timeout_seconds: 120)
        @uri = URI.parse(api_url)
        @model = model
        @timeout_seconds = timeout_seconds
      end

      def generate(prompt:)
        response = http.request(build_request(prompt))
        File.write(File.join(Rails.root, "tmp", "ollama_prompt.txt"), prompt, mode: "w")

        raise LLM::Errors::ProviderError, "Ollama returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s
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
            prompt: prompt,
            stream: false,
            format: "json",
            options: {
              temperature: 0.1
            }
          }.to_json
        end
      end
    end
  end
end
