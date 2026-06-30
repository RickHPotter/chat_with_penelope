# frozen_string_literal: true

module Prompts
  module Compact
    class Explain < Base
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: explain this French grammar topic.

          Topic/question:
          #{user_message}

          In both languages include:
          # Rule
          # Explanation
          # Examples
          # Common Mistake

          Never invent grammar rules. Prefer standard French used in France.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
