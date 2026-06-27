# frozen_string_literal: true

module Clients
  class Ollama
    def initialize(model = nil)
      @uri = URI(Rails.application.config.chat["chat_api_url"])
      @model = model || Rails.application.config.chat["chat_model"]
    end

    def request(chat:, prompt:, cached_context:, &)
      request = build_request(chat:, prompt:, cached_context:)
      send_request(request, &)
    end

    private

    def build_request(chat:, prompt:, cached_context:)
      request = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json")
      request.body = {
        model: @model,
        prompt: TutorPrompt.build(chat:, user_message: prompt),
        context: cached_context,
        think: false,
        stream: true,
        options: { temperature: 0.3 }
      }.to_json

      Rails.logger.info("🤖 #{request.body}")

      request
    end

    def send_request(request)
      Net::HTTP.start(@uri.hostname, @uri.port) do |http|
        http.request(request) do |response|
          response.read_body do |chunk|
            encoded_chunk = chunk.force_encoding("UTF-8")
            Rails.logger.info("✅ #{encoded_chunk}")
            yield encoded_chunk if block_given?
          end
        end
      end
    end
  end
end
