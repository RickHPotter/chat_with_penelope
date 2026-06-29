# frozen_string_literal: true

module Prompts
  class Base
    DEFAULT_LANGUAGE = "English"
    LANGUAGE_NAMES = {
      "fr" => "French",
      "es" => "Spanish",
      "it" => "Italian"
    }.freeze

    def self.build(chat:, user_message:, messages: [])
      new(chat:, user_message:, messages:).build
    end

    def self.build_conversation(messages)
      new(chat: nil, user_message: nil, messages:).send(:conversation)
    end

    def initialize(chat:, user_message:, messages: [])
      @chat = chat
      @user_message = user_message
      @messages = messages
    end

    private

    attr_reader :chat, :user_message, :messages

    def target_language
      LANGUAGE_NAMES.fetch(chat.target_language, chat.target_language)
    end

    def base_prompt
      <<~PROMPT
        You are a patient French tutor.

        ## Learner profile

        * Native language: #{DEFAULT_LANGUAGE}
        * Target language: #{target_language}
        * Current level: Beginner

        ## Instructions

        * Answer only the latest learner request.
        * Use the conversation history only as context.
        * Do not repeat previous answers.
        * Do not reveal reasoning or internal analysis.
        * Prefer standard French used in France.
        * Mention regional variants only when they are directly relevant.
        * The `default_language` value must be written in English.
        * The `target_language` value must be written in #{target_language}.
        * When writing in #{target_language}, do not add English translations in parentheses after #{target_language} words.
        * When writing in English, it is acceptable to include #{target_language} terms with English explanations.

        ## Output format

        Return exactly one JSON object.

        Do not output any text before or after the JSON.

        The JSON must be valid and parseable.

        Schema

        {
          "default_language": string,
          "target_language": string
        }

        Markdown may be used inside the JSON strings.
      PROMPT
    end

    def conversation_section
      <<~PROMPT
        Conversation history:

        #{conversation.presence || "None"}
      PROMPT
    end

    def conversation
      messages.map { |message| build_turn(message) }.join("\n\n")
    end

    def build_turn(message)
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
  end
end
