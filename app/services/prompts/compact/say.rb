# frozen_string_literal: true

module Prompts
  module Compact
    class Say < Base
      # Prompt budget: keep the complete prompt below 1,500 words for local models.
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: say this English sentence naturally in French.

          English:
          #{user_message}

          `default_language` must be an empty string.

          `target_language` must include:
          # Translation
          Give one natural French sentence first.

          # Note
          Briefly explain one important choice, such as register, tense, or word order.

          Include `# Alternative` only if another phrasing is genuinely common or changes register.
          Do not provide more than one alternative.
          Do not translate the French sentence back into English.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
