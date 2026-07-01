# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "fileutils"

module TextToSpeech
  class Error < StandardError; end

  Result = Struct.new(:input_text, :output_path, :audio_url, :response_body, keyword_init: true)

  class Client
    DEFAULT_API_URL = "http://127.0.0.1:8000/synthesize"
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 120
    DEFAULT_WRITE_TIMEOUT = 30

    def initialize(
      api_url: ENV.fetch("TTS_API_URL", DEFAULT_API_URL),
      open_timeout: ENV.fetch("TTS_OPEN_TIMEOUT", DEFAULT_OPEN_TIMEOUT).to_i,
      read_timeout: ENV.fetch("TTS_READ_TIMEOUT", DEFAULT_READ_TIMEOUT).to_i,
      write_timeout: ENV.fetch("TTS_WRITE_TIMEOUT", DEFAULT_WRITE_TIMEOUT).to_i
    )
      @api_url = api_url
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
    end

    def synthesize(input_text:, output_basename:)
      output_path = Rails.root.join("public", "tts", output_basename).to_s
      FileUtils.mkdir_p(File.dirname(output_path))

      response = post_json(
        input_text:,
        output_path:
      )

      raise Error, "TTS API failed with #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      raise Error, "TTS API did not create #{output_path}" unless File.exist?(output_path)

      Result.new(
        input_text:,
        output_path:,
        audio_url: "/tts/#{File.basename(output_path)}",
        response_body: response.body
      )
    end

    private

    attr_reader :api_url, :open_timeout, :read_timeout, :write_timeout

    def post_json(payload)
      uri = URI.parse(api_url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        http.write_timeout = write_timeout if http.respond_to?(:write_timeout=)

        http.request(request)
      end
    rescue Net::OpenTimeout
      raise Error, "TTS API connection timed out after #{open_timeout}s"
    rescue Net::ReadTimeout
      raise Error, "TTS API response timed out after #{read_timeout}s"
    rescue Net::WriteTimeout
      raise Error, "TTS API request write timed out after #{write_timeout}s"
    rescue SystemCallError, IOError, Timeout::Error => e
      raise Error, e.message
    end
  end
end
