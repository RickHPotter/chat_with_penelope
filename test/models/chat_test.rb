# frozen_string_literal: true

require "test_helper"

# == Schema Information
#
# Table name: chats
# Database name: primary
#
#  id              :bigint           not null, primary key
#  target_language :string
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class ChatTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
