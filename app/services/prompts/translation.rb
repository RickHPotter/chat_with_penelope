# frozen_string_literal: true

module Prompts
  class Translation < Base
    def build
      <<~PROMPT
        #{base_prompt}

        The learner has explicitly requested a translation.

        The translation direction is provided separately.

        Do not determine the learner's intent.

        ## Task

        #{direction_instructions}

        Prefer natural translations over literal ones unless the literal translation is helpful.

        In `target_language`, do not add English translations in parentheses after French words.

        Do not write patterns like `la rue (street)` in `target_language`.

        #{conversation_section}

        Direction:

        #{direction_label}

        Input:

        #{user_message}
      PROMPT
    end

    private

    def direction_instructions
      if french_to_english?
        <<~TEXT
          Translate from French to English.

          The value of `default_language` must provide the English translation.

          The value of `target_language` must:

          * Explain the French sentence.
          * Include a grammar breakdown.
        TEXT
      else
        <<~TEXT
          Translate from English to French.

          The value of `default_language` must be an empty string.

          The value of `target_language` must use this structure.

          # Translation

          # Grammar Breakdown

          # Notes

          # Alternative Translations

          Include alternative translations only if useful.
        TEXT
      end
    end

    def direction_label
      french_to_english? ? "French to English" : "English to French"
    end

    def french_to_english?
      MessageClassifier.mostly_french?(user_message)
    end
  end
end
