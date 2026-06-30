# frozen_string_literal: true

module Prompts
  module Compact
    class Say < Base
      def build
        <<~PROMPT
          #{compact_base_prompt}

          Task: say this English sentence naturally in French.

          English:
          #{user_message}

          `default_language` must be an empty string.

          `target_language` must include:
          # Translation
          # Note
          # Alternative
          Only include an alternative if it is useful.

          #{compact_json_reminder}
        PROMPT
      end
    end
  end
end
