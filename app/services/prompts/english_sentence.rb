# frozen_string_literal: true

module Prompts
  class EnglishSentence < Base
    def build
      <<~PROMPT
        #{base_prompt}

        The learner has submitted an English sentence.

        Do not determine the learner's intent.

        ## Task

        The value of `default_language` must be an empty string.

        The value of `target_language` must contain:

        # Translation

        Provide a natural French translation.

        # Grammar Breakdown

        Break down the translated French sentence.

        Explain the grammatical role of each important word.

        # Notes

        Explain any important grammar choices.

        # Alternative Translations

        Optionally provide one or two natural alternatives if they are commonly used.

        Prefer natural French over literal translations.

        Sentence:

        #{user_message}
      PROMPT
    end
  end
end
