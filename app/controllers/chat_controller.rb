# frozen_string_literal: true

class ChatController < ApplicationController
  before_action :set_chat

  def show
    @messages = @chat.messages.chronological
  end

  def create_message
    result = ChatResponder.new(chat: @chat).submit_message_async(content: message_params[:content])

    if result.response_message.present?
      render turbo_stream: create_message_stream(result), status: :ok
    else
      render turbo_stream: turbo_stream.update(
        "chat_errors",
        partial: "chat/errors",
        locals: { error_message: result.error_message }
      ), status: :unprocessable_entity
    end
  end

  def reprompt
    result = ChatResponder.new(chat: @chat).regenerate_message(message_id: params[:id])

    if result.response_message&.assistant?
      render turbo_stream: reprompt_stream(result), status: :ok
    else
      render turbo_stream: turbo_stream.append(
        "messages",
        partial: "chat/message",
        locals: { message: result.response_message }
      ), status: :ok
    end
  end

  def cancel
    message = ChatResponder.new(chat: @chat).cancel_generation(message_id: params[:id])

    render turbo_stream: turbo_stream.replace(
      helpers.dom_id(message),
      partial: "chat/message",
      locals: { message: }
    ), status: :ok
  end

  private

  def set_chat
    @chat = Chat.default_chat
  end

  def message_params
    params.require(:message).permit(:content)
  end

  def create_message_stream(result)
    [
      turbo_stream.append("messages", partial: "chat/message", locals: { message: result.user_message }),
      turbo_stream.append("messages", partial: "chat/message", locals: { message: result.response_message }),
      turbo_stream.update("composer", partial: "chat/composer", locals: { chat: @chat, message: Message.new }),
      turbo_stream.update("chat_errors", partial: "chat/errors", locals: { error_message: nil })
    ]
  end

  def reprompt_stream(result)
    [
      turbo_stream.replace(
        helpers.dom_id(result.response_message),
        partial: "chat/message",
        locals: { message: result.response_message }
      ),
      turbo_stream.update("chat_errors", partial: "chat/errors", locals: { error_message: nil })
    ]
  end
end
