# frozen_string_literal: true

require "test_helper"

module LLM
  module Providers
    class LMStudioTest < ActiveSupport::TestCase
      test "normalizes OpenAI-compatible chat completion response" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )
        body = JSON.generate(
          choices: [
            {
              message: {
                content: JSON.generate(default_language: "Hello.", target_language: "Bonjour.")
              }
            }
          ]
        )

        normalized = provider.send(:normalize_response, body)

        assert_equal(
          { "response" => JSON.generate(default_language: "Hello.", target_language: "Bonjour.") },
          JSON.parse(normalized)
        )
      end

      test "builds request with json schema response format" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )

        request = provider.send(:build_request, "Return JSON.")
        body = JSON.parse(request.body)

        assert_equal "frenchgemma-3-4b-instruct", body.fetch("model")
        assert_equal "json_schema", body.dig("response_format", "type")
        assert_equal "tutor_response", body.dig("response_format", "json_schema", "name")
        assert_equal %w[default_language target_language], body.dig("response_format", "json_schema", "schema", "required")
        assert_equal false, body.fetch("stream")
        assert_equal 0.1, body.fetch("temperature")
        assert_equal "Return JSON.", body.dig("messages", 0, "content")
      end

      test "raises malformed response when content is missing" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )

        assert_raises LLM::Errors::MalformedResponseError do
          provider.send(:normalize_response, JSON.generate(choices: []))
        end
      end
    end
  end
end
