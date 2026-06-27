# frozen_string_literal: true

module Prompts
  class Tutor
    DEFAULT_LANGUAGE = "English"
    LANGUAGE_NAMES = {
      "fr" => "French",
      "es" => "Spanish",
      "it" => "Italian"
    }.freeze

    def self.build(chat:, user_message:, messages: [])
      target_language = LANGUAGE_NAMES.fetch(chat.target_language)
      conversation = build_conversation(messages)

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

    def self.build_conversation(messages)
      messages.map { |message| build_turn(message) }.join("\n\n")
    end
    private_class_method :build_conversation

    def self.build_turn(message)
      case message.role
      when "user"
        "Learner: #{message.content_default_language}"
      when "assistant"
        <<~TURN.strip
          Assistant (#{DEFAULT_LANGUAGE}):
          #{message.content_default_language}

          Assistant (#{message.target_language_name}):
          #{message.content_target_language}
        TURN
      when "system"
        "System: #{message.content_default_language}"
      else
        "#{message.role}: #{message.content_default_language}"
      end
    end
    private_class_method :build_turn
  end
end
