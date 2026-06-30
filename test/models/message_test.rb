# frozen_string_literal: true

require "test_helper"

# == Schema Information
#
# Table name: messages
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  content_default_language :text
#  content_target_language  :text
#  content_thinking         :text
#  generation_status        :string           default("complete"), not null
#  prompt_metadata          :jsonb            not null
#  raw_response             :text
#  role                     :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  chat_id                  :bigint           not null
#
# Indexes
#
#  index_messages_on_chat_id  (chat_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#
class MessageTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
