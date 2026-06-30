# frozen_string_literal: true

module Prompts
  class FrenchSentence < Base
    def build
      <<~PROMPT
        #{base_prompt}

        The learner has submitted a French sentence.

        Do not determine the learner's intent.

        ## Task

        The value of `default_language` must contain the full answer in English.

        The value of `target_language` must contain the same full answer in French.

        Both values must use this structure:

        # Natural Translation

        Provide a natural English translation in `default_language`.

        Provide the same translation in French in `target_language`.

        Do not repeat the translation as its own explanation.

        # Correction

        State whether the French sentence is grammatically correct.

        If it is incorrect:

        * State that it is incorrect.
        * Provide exactly one corrected sentence.
        * Explain every correction individually.

        If it is correct:

        * State that it is correct.
        * Briefly explain why.

        If the grammatically corrected sentence is less idiomatic than another common form, include both:

        * Corrected sentence
        * More natural sentence

        Do not list duplicate alternatives.

        # Why

        Explain the correction directly.

        Do not call nouns, articles, adjectives, or street-name elements "prepositions".

        Never alter capitalization or apostrophes inside proper nouns unless the learner's error is specifically inside the proper noun.

        For example, Dumas must stay Dumas, not D'umas.

        # Grammar Breakdown

        Break down every important French word.

        For example:

        * Je — subject pronoun
        * viens — verb, present tense of *venir*
        * demain — adverb

        # Notes

        Include additional grammar notes only if they help the learner.

        Do not include synonyms unless the learner explicitly asks for synonyms.

        Keep explanations concise and suitable for a beginner.

        Important language rule:

        * `default_language` must be English.
        * `target_language` must be French.
        * In `target_language`, do not write entries like `rue (street)` or `J'habite (I live)`.
        * In `target_language`, explain French words using French, for example `rue — nom féminin`.
        * In `target_language`, do not write entries like `Je (je)`, `rue (rue)`, or `correcte (correcte)`.
        * In `target_language`, do not use bilingual arrows unless the two sides are different languages.

        Sentence:

        #{user_message}

        #{strict_json_reminder}
      PROMPT
    end
  end
end
