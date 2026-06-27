Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "/chat" => "chat#show", as: :chat
  post "/chat/messages" => "chat#create_message", as: :chat_messages
  post "/chat/messages/:id/reprompt" => "chat#reprompt", as: :chat_message_reprompt

  root "chat#show"
end
