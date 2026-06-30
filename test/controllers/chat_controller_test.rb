# frozen_string_literal: true

require "test_helper"

class ChatControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get root_url
    assert_response :success
  end

  test "create message updates composer frame contents instead of replacing the frame" do
    post chat_messages_url,
      params: { message: { content: "/define gauche" } },
      as: :turbo_stream

    assert_response :success
    assert_includes response.body, '<turbo-stream action="update" target="composer">'
    assert_no_match(/<turbo-stream action="replace" target="composer">/, response.body)
  end
end
