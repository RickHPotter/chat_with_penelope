# frozen_string_literal: true

module Prompts
  module Compact
    class Define < Base
      # Prompt budget: keep the complete prompt below 1,500 words for local models.
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: define one vocabulary item for a French learner.

          Expression:
          #{user_message}

          Direction rules:
          - If the expression is French, explain that exact French word/expression.
          - If the expression is clearly English, explain the best French equivalent(s).
          - Do not invert the direction. For `gauche`, do not start the French answer with `Le mot anglais "left"`.
          - In the French answer, start with the submitted expression when it is French.
          - Use `Le mot anglais ...` only when the submitted expression itself is English.

          In both languages include:
          # Short Answer
          Give the most useful meaning first. Name the source expression correctly.

          # Meanings
          If there are multiple common meanings, list them by usefulness/frequency.

          # Grammar
          Include part of speech and agreement/gender/infinitive when relevant.
          For adjectives, mention feminine/plural forms if useful.

          # Examples
          Give three short examples.
          In English output, examples may include translations.
          In French output, examples must be French-only; do not add English in parentheses.

          # Common Confusion
          Include only if genuinely helpful.
          For `droit`, mention straight/right/law/rights when relevant.
          For street direction, prefer `tout droit`; for right side, prefer `à droite`.
          For `gauche`, mention `à gauche`, `la gauche`, and avoid confusing it with English `left` as a source word.

          Avoid translation-only breakdowns. Teach French roles:
          `gauche` = adjective/noun/direction word, not just `left`.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
