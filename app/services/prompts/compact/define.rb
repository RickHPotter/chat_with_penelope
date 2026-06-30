# frozen_string_literal: true

module Prompts
  module Compact
    class Define < Base
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: explain this French vocabulary item or English-to-French lookup.

          Expression:
          #{user_message}

          In both languages include:
          # Short Answer
          Give the most useful meaning first.

          # Meanings
          If there are multiple common meanings, list them by usefulness/frequency.

          # Grammar
          Include part of speech and agreement/gender/infinitive when relevant.

          # Examples
          Give three short examples.

          # Common Confusion
          Include only if helpful. For `droit`, mention straight/right/law/rights when relevant.
          For street direction, prefer `tout droit`; for right side, prefer `à droite`.

          In French output, if the learner asked about an English word, start with:
          `Le mot anglais ...`

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
