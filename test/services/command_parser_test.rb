# frozen_string_literal: true

require "test_helper"

class CommandParserTest < ActiveSupport::TestCase
  test "parses validate command" do
    result = CommandParser.call("/validate J'habite en rue Dumas")

    assert result.matched?
    assert_equal "validate", result.command
    assert_equal :french_sentence, result.intent
    assert_equal "J'habite en rue Dumas", result.input
  end

  test "parses command aliases" do
    result = CommandParser.call("/check C'est la correct rue?")

    assert result.matched?
    assert_equal "check", result.command
    assert_equal :french_sentence, result.intent
  end

  test "ignores unknown commands" do
    result = CommandParser.call("/unknown bonjour")

    assert_not result.matched?
    assert_nil result.command
    assert_equal "/unknown bonjour", result.input
  end
end
