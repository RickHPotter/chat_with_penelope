# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  content_default_language :text
#  content_target_language  :text
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
class Message < ApplicationRecord
  belongs_to :chat

  validates :role, presence: true, inclusion: { in: %w[user assistant system] }
  validates :content_default_language, presence: true, unless: :assistant?
  validates :content_target_language, presence: true
  validates :raw_response, presence: true, if: :assistant?

  scope :chronological, -> { order(:created_at, :id) }

  def assistant?
    role == "assistant"
  end

  def user?
    role == "user"
  end

  def system?
    role == "system"
  end

  def default_language_content
    content_default_language
  end

  def target_language_content
    content_target_language
  end

  def target_language_name
    Prompts::Tutor::LANGUAGE_NAMES.fetch(chat.target_language, chat.target_language)
  end
end
