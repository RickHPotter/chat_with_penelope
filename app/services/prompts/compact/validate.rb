# frozen_string_literal: true

module Prompts
  module Compact
    class Validate < Base
      # Prompt budget: keep the complete prompt below 1,500 words for local models.
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: validate this French sentence.

          Sentence:
          #{user_message}

          Your answer must discuss this exact sentence, not the JSON schema.
          Mention whether `#{user_message}` is correct or incorrect.

          In both languages include:
          # Correction
          Start with **Correct** or **Incorrect**.
          If incorrect, give exactly one corrected sentence.
          Add confidence as `Confidence: High`, `Medium`, or `Low`.

          # Why
          Explain the correction briefly with 1-3 bullets.
          Do not call `rue` or street-name elements prepositions.
          Do not alter proper nouns, for example Dumas must stay Dumas.

          # Breakdown
          Explain French roles, not just translations.
          Good: `Je` — subject pronoun.
          Good: `habite` — present tense of `habiter`.
          Bad: `Je` — I.

          Include `# More Natural` only if there is a genuinely more natural spoken alternative.

          Do not include synonyms unless asked.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
