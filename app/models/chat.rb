# frozen_string_literal: true

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
class Chat < ApplicationRecord
  has_many :messages, dependent: :destroy

  broadcasts_to ->(chat) { [ chat, "messages" ] }

  validates :title, :target_language, presence: true

  def self.default_chat
    first_or_create!(title: "French Tutor", target_language: "fr")
  end
end
