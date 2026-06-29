# frozen_string_literal: true

require "test_helper"

module LLM
  class ClientTest < ActiveSupport::TestCase
    test "uses ollama provider by default" do
      with_chat_config("chat_provider" => "ollama") do
        provider = Client.new.send(:default_provider)

        assert_instance_of Providers::Ollama, provider
      end
    end

    test "uses lm studio provider when configured" do
      with_chat_config(
        "chat_provider" => "lm_studio",
        "chat_api_url" => "http://127.0.0.1:1234/v1/chat/completions",
        "chat_model" => "frenchgemma-3-4b-instruct"
      ) do
        provider = Client.new.send(:default_provider)

        assert_instance_of Providers::LMStudio, provider
      end
    end

    private

    def with_chat_config(overrides)
      original_config = Rails.application.config.chat
      Rails.application.config.chat = original_config.merge(overrides)

      yield
    ensure
      Rails.application.config.chat = original_config
    end
  end
end
