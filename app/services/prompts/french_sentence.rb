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

        Both values must include:

        # Translation

        Provide a natural English translation in `default_language`.

        Provide the same translation explanation in French in `target_language`.

        # Grammar Validation

        State whether the French sentence is grammatically correct.

        If it is incorrect:

        * State that it is incorrect.
        * Provide the corrected sentence.
        * Explain every correction individually.

        If it is correct:

        * State that it is correct.
        * Briefly explain why.

        # Grammar Breakdown

        Break down every important French word.

        For example:

        * Je — subject pronoun
        * viens — verb, present tense of *venir*
        * demain — adverb

        # Notes

        Include additional grammar notes only if they help the learner.

        # Synonyms

        Optionally provide useful synonyms for important words.

        Keep explanations concise and suitable for a beginner.

        Important language rule:

        * `default_language` must be English.
        * `target_language` must be French.
        * In `target_language`, do not write entries like `rue (street)` or `J'habite (I live)`.
        * In `target_language`, explain French words using French, for example `rue — nom féminin`.

        #{conversation_section}

        Sentence:

        #{user_message}
      PROMPT
    end
  end
end
