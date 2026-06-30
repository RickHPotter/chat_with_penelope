# frozen_string_literal: true

module Prompts
  class Grammar < Base
    def build
      <<~PROMPT
        #{base_prompt}

        The learner has asked a grammar question.

        Do not determine the learner's intent.

        ## Task

        Answer the question directly.

        The value of `default_language` must contain the explanation in English.

        The value of `target_language` must contain the same explanation in French.

        In `target_language`, do not add English translations in parentheses after French words.

        Do not write patterns like `rue (street)` or `J'habite (I live)` in `target_language`.

        Do not write same-language arrows like `C'est la rue correcte → C'est la rue correcte` in `target_language`.

        Use this structure.

        # Rule

        State the grammar rule.

        # Explanation

        Explain the rule clearly.

        # Examples

        Provide several natural examples.

        # Common Mistakes

        Mention common learner mistakes.

        # Exceptions

        Include exceptions only when genuine exceptions exist.

        Never invent grammar rules.

        If multiple correct forms exist, explain which one is most common in France.

        Question:

        #{user_message}
      PROMPT
    end
  end
end
