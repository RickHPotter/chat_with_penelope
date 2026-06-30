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
    assert_includes prompt, "# Correction"
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
    assert_includes prompt, "do not write entries like `Je (je)`"
    assert_no_match(/Sentence:\n\nis this grammatically correct/, prompt)
  end

  test "dispatches vocabulary questions to the vocabulary prompt" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "What does comprendre mean?", messages: [])

    assert_includes prompt, "The learner has asked a vocabulary question."
    assert_includes prompt, "Expression:"
    assert_includes prompt, "# Word or Expression"
  end

  test "vocabulary prompt includes lookup mode for single words" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "straight en français", messages: [])

    assert_includes prompt, "The learner has asked a vocabulary question."
    assert_includes prompt, "Expression:\n\nstraight"
    assert_includes prompt, "Lookup mode:\n\nsingle_word"
    assert_includes prompt, "Acknowledge when the word has multiple common meanings."
    assert_includes prompt, "Le mot anglais **straight**"
    assert_includes prompt, "Do not write same-language arrows"
    assert_includes prompt, "Do not use property names like french_language"
  end

  test "vocabulary prompt includes usage mode instructions for follow-up questions" do
    prompt = Prompts::Tutor.build(
      chat: @chat,
      user_message: "wasnt droit the translation for right? what about straight as in going straight in the street",
      messages: []
    )

    assert_includes prompt, "The learner has asked a vocabulary question."
    assert_includes prompt, "Lookup mode:\n\nusage"
    assert_includes prompt, "For street directions, prefer `tout droit`"
    assert_includes prompt, "For right side, prefer `à droite`"
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

  test "uses compact validate prompt for validate slash command" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "/validate J'habite en rue Dumas", messages: [])

    assert_includes prompt, "Task: validate this French sentence."
    assert_includes prompt, "Sentence:\nJ'habite en rue Dumas"
    assert_includes prompt, "Bad output:"
    assert_includes prompt, '{"default_language":"English","target_language":"French"}'
    assert_includes prompt, "Your answer must discuss this exact sentence, not the JSON schema."
    assert_includes prompt, "Mention whether `J'habite en rue Dumas` is correct or incorrect."
    assert_includes prompt, "The values must be the actual tutor answer text, not language names."
    assert_no_match(/The learner has submitted a French sentence/, prompt)
  end

  test "uses compact define prompt for define slash command" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "/define straight", messages: [])

    assert_includes prompt, "Task: explain this French vocabulary item"
    assert_includes prompt, "Expression:\nstraight"
    assert_includes prompt, "For `droit`, mention straight/right/law/rights"
    assert_no_match(/The learner has asked a vocabulary question/, prompt)
  end

  test "uses compact explain prompt for explain slash command" do
    prompt = Prompts::Tutor.build(chat: @chat, user_message: "/explain le passé composé", messages: [])

    assert_includes prompt, "Task: explain this French grammar topic."
    assert_includes prompt, "Topic/question:\nle passé composé"
  end

  test "does not include existing conversation history" do
    message = @chat.messages.create!(
      role: "user",
      content_default_language: "Bonjour",
      content_target_language: "Bonjour"
    )

    prompt = Prompts::Tutor.build(chat: @chat, user_message: "Je suis fatigué.", messages: [message])

    assert_no_match(/Conversation history:/, prompt)
    assert_no_match(/Learner: Bonjour/, prompt)
  end
end
