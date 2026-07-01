# frozen_string_literal: true

require "test_helper"

class TextToSpeechClientTest < ActiveSupport::TestCase
  test "stores configured http timeouts" do
    client = TextToSpeech::Client.new(
      open_timeout: 3,
      read_timeout: 180,
      write_timeout: 45
    )

    assert_equal 3, client.send(:open_timeout)
    assert_equal 180, client.send(:read_timeout)
    assert_equal 45, client.send(:write_timeout)
  end
end
