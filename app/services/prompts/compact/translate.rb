# frozen_string_literal: true

module Prompts
  module Compact
    class Translate < Base
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: translate this text naturally.

          Text:
          #{user_message}

          If the text is French, put the English translation in `default_language`
          and a brief French explanation in `target_language`.

          If the text is English, put an empty string in `default_language`
          and the French translation plus a brief note in `target_language`.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
