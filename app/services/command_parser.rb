# frozen_string_literal: true

class CommandParser
  Result = Struct.new(:matched?, :command, :intent, :input, keyword_init: true)

  COMMANDS = {
    "validate" => :french_sentence,
    "check" => :french_sentence,
    "correct" => :french_sentence,
    "define" => :vocabulary,
    "explain" => :grammar,
    "translate" => :translation,
    "say" => :english_sentence,
    "chat" => :conversation
  }.freeze

  def self.call(text)
    new(text).call
  end

  def initialize(text)
    @text = text.to_s.strip
  end

  def call
    match = text.match(%r{\A/([a-z_]+)(?:\s+(.+))?\z}i)
    return unmatched unless match

    command = match[1].downcase
    intent = COMMANDS[command]
    return unmatched unless intent

    Result.new(
      matched?: true,
      command: command,
      intent: intent,
      input: match[2].to_s.strip
    )
  end

  private

  attr_reader :text

  def unmatched
    Result.new(matched?: false, command: nil, intent: nil, input: text)
  end
end
