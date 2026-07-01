# frozen_string_literal: true

class ChatMessageBroadcaster
  def replace(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ message.chat, "messages" ],
      target: ActionView::RecordIdentifier.dom_id(message),
      partial: "chat/message",
      locals: { message: }
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ChatMessageBroadcaster] replace failed for message #{message.id}: #{e.class} #{e.message}"
    )
  end

  def append_stream(message, target_suffix, text)
    return if text.blank?

    Turbo::StreamsChannel.broadcast_append_to(
      [ message.chat, "messages" ],
      target: ActionView::RecordIdentifier.dom_id(message, target_suffix),
      html: ERB::Util.html_escape(text)
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ChatMessageBroadcaster] append failed for message #{message.id}: #{e.class} #{e.message}"
    )
  end

  def update_stream(message, target_suffix, html)
    Turbo::StreamsChannel.broadcast_update_to(
      [ message.chat, "messages" ],
      target: ActionView::RecordIdentifier.dom_id(message, target_suffix),
      html:
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ChatMessageBroadcaster] update failed for message #{message.id}: #{e.class} #{e.message}"
    )
  end
end
