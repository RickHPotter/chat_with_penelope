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

  validates :title, :target_language, presence: true
end
