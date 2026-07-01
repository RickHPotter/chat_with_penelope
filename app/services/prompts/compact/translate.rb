# frozen_string_literal: true

module Prompts
  module Compact
    class Translate < Base
      # Prompt budget: keep the complete prompt below 1,500 words for local models.
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: translate this text naturally.

          Text:
          #{user_message}

          First decide the source language from the text itself.

          If the text is French:
          - `default_language` must include `# Translation` with the English translation.
          - `default_language` should be only the translation, with no grammar explanation unless needed for ambiguity.
          - `target_language` must not translate the sentence again.
          - `target_language` must include `# Structure` and `# Explanation`.

          For French `target_language`:
          # Structure
          Explain the sentence portion by portion in French.
          Use bullets like `J'ai emprunté` — passé composé de `emprunter`.
          Separate connectors from clauses when useful.
          Good: `mais` — conjonction d'opposition.
          Good: `elle ne démarre pas` — sujet + négation + verbe au présent.
          Bad: `mais elle ne démarre pas` — conjonction + sujet + négation + verbe.
          Avoid circular explanations like `rue` — rue.
          Prefer useful French explanations like `rue` — voie de circulation.

          # Explanation
          Explain important words and the whole sentence meaning in French.
          Include 2-4 bullets:
          - Meaning of key words or expressions, not just grammar labels.
          - What the whole sentence communicates.
          - Why important grammar choices matter only if useful.
          For `emprunter`, explain temporary use of something that belongs to someone else.
          For `ne démarre pas`, explain that the vehicle does not start/work.
          Mention the situation: the speaker borrowed a friend's car and has a problem because it will not start.

          If the text is English:
          - `default_language` must be an empty string.
          - `target_language` must include `# Traduction` with the French translation.

          For English text, include `# Note` only for an important nuance, register issue, or non-literal phrasing.
          Do not add generic vocabulary lists unless asked.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
