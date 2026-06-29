# frozen_string_literal: true

module Prompts
  class Vocabulary < Base
    def build
      <<~PROMPT
        #{base_prompt}

        The learner has asked a vocabulary question.

        The expression to explain will be provided separately.

        Do not determine the learner's intent.

        ## Task

        Explain the expression in both languages.

        The value of `default_language` must contain the explanation in English.

        The value of `target_language` must contain the same explanation in French.

        In `target_language`, do not add English translations in parentheses after French words.

        Do not write patterns like `la rue (street)` in `target_language`.

        In `default_language`, parenthetical English explanations are allowed when useful.

        Use the following structure.

        # Word or Expression

        # Part of Speech

        Examples:

        * noun
        * verb
        * adjective
        * adverb
        * expression

        If applicable include:

        * gender
        * infinitive
        * adjective agreement

        # Meaning

        Explain the meaning clearly.

        If there are multiple meanings, list the common ones first.

        # Usage

        Explain when the word is typically used.

        Mention register if relevant.

        Examples:

        * formal
        * informal
        * literary

        # Examples

        Provide three natural example sentences.

        # Related Words

        Optionally include related vocabulary or synonyms.

        Write explanations for beginner learners.

        #{conversation_section}

        Expression:

        #{user_message}
      PROMPT
    end
  end
end
