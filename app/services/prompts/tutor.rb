# frozen_string_literal: true

module Prompts
  class Tutor
    DEFAULT_LANGUAGE = Base::DEFAULT_LANGUAGE
    LANGUAGE_NAMES = Base::LANGUAGE_NAMES

    def self.build(chat:, user_message:, messages: [])
      classification = MessageClassifier.classify(user_message)
      intent = classification.intent

      return legacy_build(chat:, user_message:, messages:) if intent == :conversation

      builder_for(intent).build(chat:, user_message: classification.input_excerpt, messages:)
    end

    def self.builder_for(intent)
      {
        french_sentence: Prompts::FrenchSentence,
        english_sentence: Prompts::EnglishSentence,
        vocabulary: Prompts::Vocabulary,
        grammar: Prompts::Grammar,
        translation: Prompts::Translation
      }.fetch(intent)
    end
    private_class_method :builder_for

    def self.legacy_build(chat:, user_message:, messages: [])
      target_language = LANGUAGE_NAMES.fetch(chat.target_language, chat.target_language)
      conversation = Prompts::Base.build_conversation(messages)

      <<~PROMPT
        You are a patient French tutor.

        Learner profile:
        - Native/explanation language: #{DEFAULT_LANGUAGE}
        - Target language: #{target_language}
        - Current level: beginner

        For every learner message, generate one assistant reply.

        Return exactly one JSON object.

        Do not output anything before or after the JSON.

        Schema:

        {
          "default_language": "<complete assistant reply in English>",
          "target_language": "<the same reply translated into French>"
        }

        Rules:
        - The values are assistant replies, NOT language names.
        - Both values must contain the complete response.
        - The French reply should be a faithful translation of the English reply.
        - Markdown is allowed inside the strings when useful.
        - Do not include explanations or reasoning.
        - The JSON must be valid and parseable.
        - When the learner asks a general question about something not related to #{target_language}, answer it as a tutor would, not as a refusal.

        Example:

        Learner: Hi

        Output:
        {
          "default_language": "Hi! How can I help you learn French today?",
          "target_language": "Bonjour ! Comment puis-je vous aider à apprendre le français aujourd'hui ?"
        }

        Conversation so far:
        #{conversation.presence || 'None'}

        Learner message:
        #{user_message}
      PROMPT
    end
    private_class_method :legacy_build
  end
end
