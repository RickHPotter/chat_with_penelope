# frozen_string_literal: true

module Prompts
  module Compact
    class Explain < Base
      # Prompt budget: keep the complete prompt below 1,500 words for local models.
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: explain this French grammar topic.

          Topic/question:
          #{user_message}

          In both languages include:
          # Rule
          State the core rule in 1-2 sentences.

          # Explanation
          Explain how it works for a beginner. Use 2-4 bullets when useful.

          # Examples
          Give 3 short examples. In English output, examples may use `French → English`.
          In French output, examples must stay French-only with short French explanations.

          # Common Mistake
          Include only one common beginner mistake.

          Never invent grammar rules. Prefer standard French used in France.
          If there are regional or register differences, mention them briefly.
          Do not include a correction unless the learner provided a sentence to correct.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
