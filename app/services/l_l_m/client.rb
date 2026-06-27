# frozen_string_literal: true

module LLM
  class Client
    def initialize(provider: default_provider)
      @provider = provider
    end

    def generate(prompt:)
      @provider.generate(prompt:)
    end

    private

    def default_provider
      LLM::Providers::Ollama.new(
        api_url: Rails.application.config.chat["chat_api_url"],
        model: Rails.application.config.chat["chat_model"]
      )
    end
  end
end
