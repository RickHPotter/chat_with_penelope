# frozen_string_literal: true

module LLM
  class Client
    def initialize(provider: default_provider)
      @provider = provider
    end

    def generate(prompt:)
      @provider.generate(prompt:)
    end

    def generate_stream(prompt:, &block)
      if @provider.respond_to?(:generate_stream)
        @provider.generate_stream(prompt:, &block)
      else
        block.call(@provider.generate(prompt:))
      end
    end

    private

    def default_provider
      provider_class.new(api_url: chat_config.fetch("chat_api_url"), model: chat_config.fetch("chat_model"))
    end

    def provider_class
      case chat_config.fetch("chat_provider")
      when "ollama"
        LLM::Providers::Ollama
      when "lm_studio"
        LLM::Providers::LMStudio
      else
        raise ArgumentError, "Unsupported chat provider: #{chat_config.fetch('chat_provider')}"
      end
    end

    def chat_config
      Rails.application.config.chat
    end
  end
end
