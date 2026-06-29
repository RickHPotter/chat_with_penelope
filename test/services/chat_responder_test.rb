# frozen_string_literal: true

require "test_helper"
require "json"

class ChatResponderTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(response)
      @response = response
    end

    def generate(prompt:)
      @response.call(prompt)
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

  test "regenerate_message overwrites the existing assistant message" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    user = chat.messages.create!(
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
    client = FakeClient.new(->(_prompt) do
      JSON.generate(
        response: JSON.generate(
          default_language: "Updated.",
          target_language: "Mis à jour."
        )
      )
    end)

    result = ChatResponder.new(chat:, client:).regenerate_message(message_id: assistant.id)

    assert result.success?
    assert_equal assistant.id, result.response_message.id
    assert_equal "Updated.", assistant.reload.content_default_language
    assert_equal "Mis à jour.", assistant.reload.content_target_language
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

  test "submit_message returns a system message when the provider is unavailable" do
    chat = Chat.create!(title: "French Tutor", target_language: "fr")
    client = FakeClient.new(->(_prompt) { raise LLM::Errors::ConnectionError, "down" })

    result = ChatResponder.new(chat:, client:).submit_message(content: "Hello")

    assert_not result.success?
    assert_equal "system", result.response_message.role
    assert_match(/unavailable/i, result.response_message.content_default_language)
  end
end
