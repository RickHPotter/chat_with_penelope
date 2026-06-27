# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  content_default_language :text
#  content_target_language  :text
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
class Message < ApplicationRecord
  belongs_to :chat

  validates :role, presence: true, inclusion: { in: %w[user assistant system] }
  validates :content_default_language, :content_target_language, presence: true
end
