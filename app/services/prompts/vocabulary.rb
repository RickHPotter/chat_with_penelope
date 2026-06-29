# frozen_string_literal: true

module Prompts
  class Vocabulary < Base
    def build
      <<~PROMPT
        #{base_prompt}

        The learner has asked a vocabulary question.

        The expression to explain and the lookup mode will be provided separately.

        Do not determine the learner's intent.

        ## Task

        Explain the expression in both languages.

        The value of `default_language` must contain the explanation in English.

        The value of `target_language` must contain the same explanation in French.

        In `target_language`, do not add English translations in parentheses after French words.

        Do not write patterns like `la rue (street)` in `target_language`.

        Do not write same-language arrows like `une ligne droite → une ligne droite` in `target_language`.

        In `target_language`, if explaining an English word, name it as an English word first.

        Example: `Le mot anglais **straight** a plusieurs traductions possibles.`

        Do not replace the English source word with only one French translation in the opening sentence.

        In `default_language`, parenthetical English explanations are allowed when useful.

        If lookup mode is `single_word`:

        * Acknowledge when the word has multiple common meanings.
        * Present the common translations or meanings in order of frequency.
        * Explain that the correct translation depends on context.
        * Avoid circular definitions like `droit means droit`.
        * Include common beginner meanings when relevant: shape, direction, direct/honest, immediate, and identity/orientation.
        * Clearly distinguish adjective, adverb, noun, and expression uses when they differ.

        If lookup mode is `expression`:

        * Explain the expression as a whole first.
        * Then explain important component words only when helpful.

        If lookup mode is `usage`:

        * Answer the learner's usage question directly.
        * Use conversation history to understand the previously discussed word.
        * Use this structure: `# Short Answer`, `# Difference`, `# Use This For`, `# Examples`, `# Common Mistake`.
        * For street directions, prefer `tout droit`, `aller tout droit`, and `continuer tout droit`.
        * For right side, prefer `à droite` and `tourner à droite`.
        * Explain that `droit` can mean straight, right, law, or rights depending on context when relevant.

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

        For ambiguous English words, do not assume there is only one French translation.

        # Usage

        Explain when the word is typically used.

        Mention register if relevant.

        Examples:

        * formal
        * informal
        * literary

        # Examples

        Provide three natural example sentences.

        In `default_language`, examples may use `English → French`.

        In `target_language`, examples must be French-only, with short French explanations when useful.

        # Related Words

        Optionally include related vocabulary or synonyms.

        Do not include weak synonyms that repeat the same word without adding meaning.

        Write explanations for beginner learners.

        #{conversation_section}

        Expression:

        #{user_message}

        Lookup mode:

        #{lookup_mode}

        #{strict_json_reminder}
      PROMPT
    end

    private

    def lookup_mode
      MessageClassifier.classify(user_message).lookup_mode ||
        (user_message.to_s.scan(/[[:alpha:]']+/).size <= 1 ? "single_word" : "expression")
    end
  end
end
