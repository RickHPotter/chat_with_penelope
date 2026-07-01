# frozen_string_literal: true

require "test_helper"
require "json"

class ChatResponderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FakeClient
    def initialize(response)
      @response = response
    end

    def generate(prompt:)
      @response.call(prompt)
    end
  end

  class FakeStreamingClient
    def initialize(chunks)
      @chunks = chunks
    end

    def generate_stream(prompt:)
      @chunks.each { |chunk| yield chunk }
    end
  end

  class FakeTTSClient
    Result = Struct.new(:input_text, :output_path, :audio_url, :response_body, keyword_init: true)

    attr_reader :requests

    def initialize
      @requests = []
    end

    def synthesize(input_text:, output_basename:)
      @requests << { input_text:, output_basename: }
      Result.new(
        input_text:,
        output_path: Rails.root.join("public", "tts", output_basename).to_s,
        audio_url: "/tts/#{output_basename}",
        response_body: "{}"
      )
    end
  end

  test "submit_message creates a user message and an assistant reply" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    response = JSON.generate(
      response: JSON.generate(
        default_language: "Hello.",
        target_language: "Bonjour."
      )
    )
    client = FakeClient.new(->(_prompt) { response })

    result = ChatResponder.new(chat:, client:).submit_message(content: "Hello")

    assert result.success?
    assert_equal 2, chat.messages.count
    assert_equal "user", result.user_message.role
    assert_equal "assistant", result.response_message.role
    assert_equal "Hello.", result.response_message.content_default_language
    assert_equal "Bonjour.", result.response_message.content_target_language
    assert_equal response, result.response_message.raw_response
  end

  test "submit_message_async creates user and generating assistant then enqueues job" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    assert_enqueued_with(job: GenerateAssistantResponseJob) do
      result = ChatResponder.new(chat:, client: FakeClient.new(->(_prompt) { raise "unused" })).submit_message_async(content: "/validate J'habite en rue Dumas")

      assert_equal "user", result.user_message.role
      assert_equal "assistant", result.response_message.role
      assert result.response_message.generating?
      assert_equal ChatResponder::STREAMING_DEFAULT_MESSAGE, result.response_message.content_default_language
      assert_equal({ "response" => "" }, JSON.parse(result.response_message.raw_response))
    end
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
  end

  test "cancel_generation marks generating message as cancelling" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    assistant = chat.messages.create!(
      role: "assistant",
      content_default_language: ChatResponder::STREAMING_DEFAULT_MESSAGE,
      content_target_language: ChatResponder::STREAMING_TARGET_MESSAGE,
      raw_response: JSON.generate(response: ""),
      generation_status: "generating"
    )

    message = ChatResponder.new(chat:).cancel_generation(message_id: assistant.id)

    assert message.cancelling?
    assert_includes message.prompt_metadata.fetch("output_warnings"), "cancellation requested"
  end

  test "stream_response_into stores readable partial json preview while generating" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    assistant = chat.messages.create!(
      role: "assistant",
      content_default_language: ChatResponder::STREAMING_DEFAULT_MESSAGE,
      content_target_language: ChatResponder::STREAMING_TARGET_MESSAGE,
      raw_response: JSON.generate(response: ""),
      generation_status: "generating"
    )
    client = FakeStreamingClient.new([
      '{"default_language":"Correct sentence: J',
      "'habite rue Dumas.",
      '","target_language":"Phrase correcte : J',
      "'habite rue Dumas.\"}"
    ])

    ChatResponder.new(chat:, client:).stream_response_into(
      assistant_message: assistant,
      user_message: "/validate J'habite en rue Dumas"
    )

    assistant.reload
    assert_equal "complete", assistant.generation_status
    assert_equal "Correct sentence: J'habite rue Dumas.", assistant.content_default_language
    assert_equal "Phrase correcte : J'habite rue Dumas.", assistant.content_target_language
  end

  test "stream_response_into handles say command by cleaning text and attaching audio url" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    assistant = chat.messages.create!(
      role: "assistant",
      content_default_language: ChatResponder::STREAMING_DEFAULT_MESSAGE,
      content_target_language: ChatResponder::STREAMING_TARGET_MESSAGE,
      raw_response: JSON.generate(response: ""),
      generation_status: "generating"
    )
    response = JSON.generate(
      response: JSON.generate(
        default_language: "",
        target_language: "J'habite rue Dumas."
      )
    )
    client = FakeClient.new(->(prompt) do
      assert_includes prompt, "You clean French text before text-to-speech."
      response
    end)
    tts_client = FakeTTSClient.new

    ChatResponder.new(chat:, client:, tts_client:).stream_response_into(
      assistant_message: assistant,
      user_message: "/say Jhabite rue Dumas."
    )

    assistant.reload
    assert_equal "complete", assistant.generation_status
    assert_equal "", assistant.content_default_language
    assert_equal "# Audio\nJ'habite rue Dumas.", assistant.content_target_language
    assert_equal "/tts/message_#{assistant.id}.wav", assistant.audio_url
    assert_equal "J'habite rue Dumas.", tts_client.requests.first.fetch(:input_text)
    assert_equal true, assistant.prompt_metadata.fetch("audio_generation")
    assert_equal "/tts/message_#{assistant.id}.wav", assistant.prompt_metadata.fetch("tts_audio_url")
  end

  test "say command falls back to deterministic cleanup when llm cleanup is malformed" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    assistant = chat.messages.create!(
      role: "assistant",
      content_default_language: ChatResponder::STREAMING_DEFAULT_MESSAGE,
      content_target_language: ChatResponder::STREAMING_TARGET_MESSAGE,
      raw_response: JSON.generate(response: ""),
      generation_status: "generating"
    )
    client = FakeClient.new(->(_prompt) { JSON.generate(response: "not json") })
    tts_client = FakeTTSClient.new

    ChatResponder.new(chat:, client:, tts_client:).stream_response_into(
      assistant_message: assistant,
      user_message: "/say Jhabite avec mon ami"
    )

    assert_equal "J'habite avec mon ami", tts_client.requests.first.fetch(:input_text)
  end

  test "stream_response_into stores thinking-only chunks while waiting for answer content" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    assistant = chat.messages.create!(
      role: "assistant",
      content_default_language: ChatResponder::STREAMING_DEFAULT_MESSAGE,
      content_target_language: ChatResponder::STREAMING_TARGET_MESSAGE,
      raw_response: JSON.generate(response: ""),
      generation_status: "generating"
    )
    client = FakeStreamingClient.new([
      { type: :thinking, text: "Role" },
      { type: :thinking, text: ":" }
    ])

    ChatResponder.new(chat:, client:).stream_response_into(
      assistant_message: assistant,
      user_message: "/validate J'habite en rue Dumas"
    )

    assistant.reload
    assert_equal "Role:", assistant.content_thinking
    assert_equal "Role:", JSON.parse(assistant.raw_response).fetch("thinking")
    assert_equal "Raw model thinking:\n\nRole:", assistant.content_default_language
    assert_equal "Raw model thinking:\n\nRole:", assistant.content_target_language
  end

  test "submit_message does not send previous conversation in prompt" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    chat.messages.create!(
      role: "user",
      content_default_language: "Previous private turn",
      content_target_language: "Previous private turn"
    )
    captured_prompt = nil
    response = JSON.generate(
      response: JSON.generate(
        default_language: "Incorrect.",
        target_language: "Incorrect."
      )
    )
    client = FakeClient.new(->(prompt) do
      captured_prompt = prompt
      response
    end)

    ChatResponder.new(chat:, client:).submit_message(content: "/validate J'habite en rue Dumas")

    assert_no_match(/Previous private turn/, captured_prompt)
    assert_includes captured_prompt, "J'habite en rue Dumas"
  end

  test "regenerate_message resets the existing assistant message and enqueues streaming job" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    chat.messages.create!(
      role: "user",
      content_default_language: "Hello",
      content_target_language: "Hello"
    )
    assistant = chat.messages.create!(
      role: "assistant",
      content_default_language: "Old",
      content_target_language: "Ancien",
      raw_response: JSON.generate(response: JSON.generate(default_language: "Old", target_language: "Ancien"))
    )
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    assert_enqueued_with(job: GenerateAssistantResponseJob) do
      result = ChatResponder.new(chat:).regenerate_message(message_id: assistant.id)

      assert result.success?
      assert_equal assistant.id, result.response_message.id
      assert assistant.reload.generating?
      assert_equal ChatResponder::STREAMING_DEFAULT_MESSAGE, assistant.content_default_language
      assert_equal ChatResponder::STREAMING_TARGET_MESSAGE, assistant.content_target_language
    end
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
  end

  test "submit_message accepts an empty default language response" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    response = JSON.generate(
      response: JSON.generate(
        default_language: "",
        target_language: "Je suis fatigué."
      )
    )
    client = FakeClient.new(->(_prompt) { response })

    result = ChatResponder.new(chat:, client:).submit_message(content: "I am tired.")

    assert result.success?
    assert_equal "", result.response_message.content_default_language
    assert_equal "Je suis fatigué.", result.response_message.content_target_language
  end

  test "submit_message repairs common language key aliases and stores warnings" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    response = JSON.generate(
      response: JSON.generate(
        default_language: "English answer.",
        french_language: "Réponse française."
      )
    )
    client = FakeClient.new(->(_prompt) { response })

    result = ChatResponder.new(chat:, client:).submit_message(content: "straight en français")

    assert result.success?
    assert_equal "English answer.", result.response_message.content_default_language
    assert_equal "Réponse française.", result.response_message.content_target_language
    assert_includes result.response_message.prompt_metadata.fetch("parse_warnings"), "used french_language instead of target_language"
    assert result.response_message.prompt_metadata.fetch("prompt_digest").present?
    assert result.response_message.prompt_metadata.fetch("prompt_preview").present?
  end

  test "submit_message parses first complete json object when response repeats json" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    duplicated_response = [
      JSON.generate(default_language: "First English.", target_language: "Premier français."),
      JSON.generate(default_language: "Second English.", target_language: "Deuxième français.")
    ].join
    client = FakeClient.new(->(_prompt) { JSON.generate(response: duplicated_response) })

    result = ChatResponder.new(chat:, client:).submit_message(content: "/validate tu va")

    assert result.success?
    assert_equal "First English.", result.response_message.content_default_language
    assert_equal "Premier français.", result.response_message.content_target_language
  end

  test "submit_message stores slash command metadata" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    response = JSON.generate(
      response: JSON.generate(
        default_language: "Incorrect.",
        target_language: "Incorrect."
      )
    )
    client = FakeClient.new(->(_prompt) { response })

    result = ChatResponder.new(chat:, client:).submit_message(content: "/validate J'habite en rue Dumas")

    assert result.success?
    assert_equal "validate", result.response_message.prompt_metadata.fetch("slash_command")
    assert_equal true, result.response_message.prompt_metadata.fetch("compact_prompt")
    assert_equal "slash_command", result.response_message.prompt_metadata.dig("classifier", "matched_rule")
    assert_equal "Prompts::Compact::Validate", result.response_message.prompt_metadata.fetch("prompt_builder")
  end

  test "submit_message stores output warnings for suspicious response patterns" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    response = JSON.generate(
      response: JSON.generate(
        default_language: "The correct sentence is 'A' or 'A'.",
        target_language: "La phrase est « J'habite rue D'umas ». rue (rue)"
      )
    )
    client = FakeClient.new(->(_prompt) { response })

    result = ChatResponder.new(chat:, client:).submit_message(content: "is this grammatically correct? -> J'habite en rue Dumas")

    warnings = result.response_message.prompt_metadata.fetch("output_warnings")

    assert_includes warnings, "target_language contains D'umas"
    assert_includes warnings, "target_language contains same-language glosses"
    assert_includes warnings, "response contains duplicate alternatives"
  end

  test "submit_message stores output warning for literal language name response" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    response = JSON.generate(
      response: JSON.generate(
        default_language: "English",
        target_language: "French"
      )
    )
    client = FakeClient.new(->(_prompt) { response })

    result = ChatResponder.new(chat:, client:).submit_message(content: "/validate J'habite en rue Dumas")

    assert_includes result.response_message.prompt_metadata.fetch("output_warnings"), "response contains literal language names instead of answers"
  end

  test "submit_message fallback stores synthetic raw response when provider raises malformed response" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    client = FakeClient.new(->(_prompt) { raise LLM::Errors::MalformedResponseError, "bad provider body" })

    result = ChatResponder.new(chat:, client:).submit_message(content: "/validate J'habite en rue Dumas")

    assert result.success?
    assert_equal ChatResponder::FALLBACK_DEFAULT_MESSAGE, result.response_message.content_default_language
    assert_equal ChatResponder::FALLBACK_TARGET_MESSAGE, result.response_message.content_target_language
    assert_equal "LLM::Errors::MalformedResponseError", JSON.parse(result.response_message.raw_response).fetch("error")
    assert_includes result.response_message.prompt_metadata.fetch("parse_warnings"), "bad provider body"
  end

  test "submit_message returns a system message when the provider is unavailable" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    client = FakeClient.new(->(_prompt) { raise LLM::Errors::ConnectionError, "down" })

    result = ChatResponder.new(chat:, client:).submit_message(content: "Hello")

    assert_not result.success?
    assert_equal "system", result.response_message.role
    assert_match(/unavailable/i, result.response_message.content_default_language)
  end
end
