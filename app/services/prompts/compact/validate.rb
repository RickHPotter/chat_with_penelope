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
          Say if it is correct. If incorrect, give exactly one corrected sentence.

          # Why
          Explain the correction briefly. Do not call `rue` or street-name elements prepositions.
          Do not alter proper nouns, for example Dumas must stay Dumas.

          # Breakdown
          Briefly explain the important French words.

          If a more natural sentence is different from the strict correction, include:
          More natural: ...

          Do not include synonyms unless asked.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
