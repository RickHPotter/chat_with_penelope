# frozen_string_literal: true

require "test_helper"

class PromptsTutorTest < ActiveSupport::TestCase
  setup do
    @chat = Chat.create!(title: "French Tutor", target_language: "fr")
  end

  test "dispatches French sentences to the French sentence prompt" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "Je suis fatigué.", messages: [])

    assert_includes prompt, "The learner has submitted a French sentence."
    assert_includes prompt, "Sentence:"
    assert_includes prompt, "# Grammar Validation"
    assert_includes prompt, "The value of `default_language` must contain the full answer in English."
    assert_includes prompt, "The value of `target_language` must contain the same full answer in French."
    assert_includes prompt, '"default_language": string'
  end

  test "extracts French sentence from validation wrapper before building prompt" do
    prompt = Prompts::Tutor.build(
      chat: @chat,
      user_message: "is this grammatically correct? -> J'habite en rue Dumas",
      messages: []
    )

    assert_includes prompt, "The learner has submitted a French sentence."
    assert_includes prompt, "Sentence:\n\nJ'habite en rue Dumas"
    assert_includes prompt, "do not write entries like `rue (street)`"
    assert_no_match(/Sentence:\n\nis this grammatically correct/, prompt)
  end

  test "dispatches vocabulary questions to the vocabulary prompt" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "What does comprendre mean?", messages: [])

    assert_includes prompt, "The learner has asked a vocabulary question."
    assert_includes prompt, "Expression:"
    assert_includes prompt, "# Word or Expression"
  end

  test "dispatches English sentences to the English sentence prompt" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "I am tired.", messages: [])

    assert_includes prompt, "The learner has submitted an English sentence."
    assert_includes prompt, "The value of `default_language` must be an empty string."
    assert_includes prompt, "# Translation"
  end

  test "keeps legacy fallback for conversation" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "Hi", messages: [])

    assert_includes prompt, "For every learner message, generate one assistant reply."
    assert_includes prompt, "Learner message:"
  end

  test "includes existing conversation history" do
    message = @chat.messages.create!(
      role: "user",
      content_default_language: "Bonjour",
      content_target_language: "Bonjour"
    )

    prompt = Prompts::Tutor.build(chat: @chat, user_message: "Je suis fatigué.", messages: [message])

    assert_includes prompt, "Conversation history:"
    assert_includes prompt, "Learner: Bonjour"
  end
end
