# frozen_string_literal: true

require "test_helper"

module LLM
  module Providers
    class LMStudioTest < ActiveSupport::TestCase
      test "normalizes responses api response" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )
        body = JSON.generate(
          output_text: JSON.generate(default_language: "Hello.", target_language: "Bonjour.")
        )

        normalized = provider.send(:normalize_response, body)

        assert_equal(
          { "response" => JSON.generate(default_language: "Hello.", target_language: "Bonjour.") },
          JSON.parse(normalized)
        )
      end

      test "builds responses api request" do
        previous_max_tokens = ENV["CHAT_MAX_TOKENS"]
        ENV["CHAT_MAX_TOKENS"] = "70"
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )

        request = provider.send(:build_request, "Return JSON.")
        body = JSON.parse(request.body)

        assert_equal "/v1/responses", request.path
        assert_equal "frenchgemma-3-4b-instruct", body.fetch("model")
        assert_equal false, body.fetch("stream")
        assert_equal 70, body.fetch("max_output_tokens")
        assert_equal({ "effort" => "none" }, body.fetch("reasoning"))
        assert_equal "Return JSON.", body.fetch("input")
        assert_not body.key?("messages")
        assert_not body.key?("response_format")
      ensure
        if previous_max_tokens
          ENV["CHAT_MAX_TOKENS"] = previous_max_tokens
        else
          ENV.delete("CHAT_MAX_TOKENS")
        end
      end

      test "builds streaming responses api request" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )

        request = provider.send(:build_request, "Return JSON.", stream: true)
        body = JSON.parse(request.body)

        assert_equal "/v1/responses", request.path
        assert_equal true, body.fetch("stream")
        assert_equal({ "effort" => "none" }, body.fetch("reasoning"))
        assert_equal "text/event-stream", request["Accept"]
        assert_equal "no-cache", request["Cache-Control"]
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

      test "parses streaming chunks" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )
        chunks = []

        provider.send(:parse_stream_chunk, "data: {\"choices\":[{\"delta\":{\"content\":\"Bon\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"jour\"}}]}\n\n") do |content|
          chunks << content
        end

        assert_equal [
          { type: :content, text: "Bon" },
          { type: :content, text: "jour" }
        ], chunks
      end

      test "parses responses api output text deltas" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/responses",
          model: "frenchgemma-3-4b-instruct"
        )
        chunks = []

        provider.send(:parse_stream_chunk, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Bon\"}\n\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"jour\"}\n\n") do |content|
          chunks << content
        end

        assert_equal [
          { type: :content, text: "Bon" },
          { type: :content, text: "jour" }
        ], chunks
      end

      test "ignores responses api lifecycle response objects" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/responses",
          model: "frenchgemma-3-4b-instruct"
        )
        chunks = []

        provider.send(:parse_stream_chunk, "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_123\",\"status\":\"in_progress\"}}\n\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"Bon\"}\n\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_123\",\"status\":\"completed\"}}\n\n") do |content|
          chunks << content
        end

        assert_equal [ { type: :content, text: "Bon" } ], chunks
      end

      test "ignores responses api full output text events while streaming" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/responses",
          model: "frenchgemma-3-4b-instruct"
        )
        chunks = []

        provider.send(:parse_stream_chunk, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Bon\"}\n\ndata: {\"type\":\"response.output_text.done\",\"output_text\":\"Bonjour\"}\n\n") do |content|
          chunks << content
        end

        assert_equal [ { type: :content, text: "Bon" } ], chunks
      end

      test "parses reasoning stream fields as thinking content" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )
        chunks = []

        provider.send(:parse_stream_chunk, "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"hidden\"}}]}\n\n") do |content|
          chunks << content
        end

        assert_equal [ { type: :thinking, text: "hidden" } ], chunks
      end

      test "parses flat text stream fields" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )
        chunks = []

        provider.send(:parse_stream_chunk, "data: {\"text\":\"Bonjour\"}\n\n") do |content|
          chunks << content
        end

        assert_equal [ { type: :content, text: "Bonjour" } ], chunks
      end

      test "buffers split streaming events until separator arrives" do
        provider = LMStudio.new(
          api_url: "http://127.0.0.1:1234/v1/chat/completions",
          model: "frenchgemma-3-4b-instruct"
        )
        buffer = +""
        chunks = []

        buffer << "data: {\"choices\":[{\"delta\":{\"content\":\"Bon"
        provider.send(:each_stream_event, buffer) do |event|
          provider.send(:parse_stream_event, event) { |content| chunks << content }
        end

        assert_empty chunks
        assert_includes buffer, "Bon"

        buffer << "jour\"}}]}\n\n"
        provider.send(:each_stream_event, buffer) do |event|
          provider.send(:parse_stream_event, event) { |content| chunks << content }
        end

        assert_equal [ { type: :content, text: "Bonjour" } ], chunks
        assert_empty buffer
      end
    end
  end
end
