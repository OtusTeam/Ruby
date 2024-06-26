# Demo Rails

http://127.0.0.1:3000/ - адрес приложения

.env - сюда прописать OpenAI ChatGPT Key для взаимодействия с API

### Команды в помощь
docker-compose build - Сборка образа с приложением
docker-compose up -d - Запуск контейнеров приложения
docker-compose exec web bash - Запуск bash внутри контейнера web
pumactl restart - Рестарт веб-сервера Puma

## Создать модели и миграции через генератор моделей. Запустить миграции внутри контейнера
bin/rails generate model Chat
bin/rails generate model Message chat:references role:integer content:string

## Дополнить модель Chat (app/models/chat.rb) новым кодом
class Chat < ApplicationRecord
  has_many :messages, dependent: :destroy
end

## Дополнить модель Message (app/models/message.rb) новым кодом
class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  belongs_to :chat

  enum role: { assistant: 1, user: 2 }

  after_create_commit :broadcast_created
  after_update_commit :broadcast_updated

  def broadcast_created
    broadcast_append_later_to(target_dom_id, partial: 'messages/message', target: target_dom_id)
  end

  def broadcast_updated
    broadcast_append_to(target_dom_id, partial: 'messages/message', target: target_dom_id)
  end

  def target_dom_id
    "#{dom_id(chat)}_messages"
  end
end


## Добавить WelcomeController с index action
bin/rails generate controller Welcome index

## Поменять config/routes.rb
root 'welcome#index'


## Добавить ChatsController с show и create actions (например, без хелпера и роута)
bin/rails generate controller Chats show create --no-helper --skip-routes

## Добавить в config/routes.rb
resources :chats, only: %i[show create]

## Дополним ChatsController (app/controllers/chats_controller.rb) новым кодом
class ChatsController < ApplicationController
  def show
    @chat = Chat.find(params[:id])
  end

  def create
    @chat = Chat.create
    redirect_to chat_path(@chat)
  end
end


## Добавить MessagesController с create action (например, без хелпера и роута)
bin/rails generate controller Messages create --no-helper --skip-routes

## Дополним MessagesController (app/controllers/messages_controller.rb) новым кодом
class MessagesController < ApplicationController
  def create
    @chat = Chat.find(params[:chat_id])
    @message = @chat.messages.create(message_params.merge(role: 'user'))

    ChatgptResponseJob.perform_later(@chat.id)

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end

## Добавить в config/routes.rb
resources :chats, only: %i[show create] do
  resources :messages, only: %i[create]
end


## Добавить app/jobs/chatgpt_response_job.rb
class ChatgptResponseJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat = Chat.find(chat_id)
    call_chatgpt(chat)
  end

  private

  def call_chatgpt(chat)
    message = create_assistant_message(chat)
    message.broadcast_created

    OpenAI::Client.new.chat(
      parameters: {
        model: 'gpt-3.5-turbo',
        messages: chat_messages_data(chat),
        temperature: 0.1,
        stream: stream_proc(message)
      }
    )
  end

  def create_assistant_message(chat)
    chat.messages.create(role: 'assistant', content: '')
  end

  def chat_messages_data(chat)
    chat.messages.map { |msg| { role: msg.role, content: msg.content } }
  end

  def stream_proc(message)
    proc do |chunk, _|
      new_content = chunk.dig('choices', 0, 'delta', 'content')
      message.update(content: message.content + new_content) if new_content
    end
  end
end

## Добавить в app/views/welcome/index.html.haml
.main
  .px-4.py-5.my-5.text-center
    %h1 Онлайн-интервьюер
    .col-lg-6.mx-auto 
      %p.lead.mb-4 Сервис помогает подготовиться к собеседованию на заданную пользователем должность
      = button_to "Начать собеседование", chats_path, method: :post, class: "btn btn-primary btn-lg"

## Добавить в app/views/chats/show.html.haml
.main
  .px-4.py-5.my-5.text-center
    %h1 Чат №#{@chat.id}
    .col-lg-6.mx-auto 
      = turbo_stream_from "#{dom_id(@chat)}_messages"
      %div{id: "#{dom_id(@chat)}_messages"}
        = render @chat.messages
  
      = render partial: "messages/form", locals: { chat: @chat }

## Добавить в app/views/messages/_form.html.haml
= turbo_frame_tag "#{dom_id(chat)}_message_form" do
  = form_with(model: Message.new, url: chat_messages_path(chat)) do |form|
    = form.text_area :content, rows: 5, cols: 80
    %br= form.button 'Отправить', type: :submit, class: 'btn btn-success'


## Добавить в app/views/messages/_message.html.haml
%div{id: "#{dom_id(message)}_messages"}
  - if message.user?
    .alert.alert-success
      = message.content
  - else
    .alert.alert-dark
      = message.content

## Добавить в app/views/nessages/create.turbo_stream.haml
= turbo_stream.append "#{dom_id(@message.chat)}_messages" do
  = render "message", message: @message
= turbo_stream.replace "#{dom_id(@message.chat)}_message_form" do
  = render "form", chat: @message.chat

## Промпт
Привет! Я хочу пройти собеседование. Сначала спроси меня, на какую должность я хочу пройти собеседование. Затем ты будешь моим интервьером. Ты задашь мне 5 вопросов, на которые я должен дать ответ. После этого сделай заключение на основе моих ответов, что мне стоит изучить, чтобы пройти собеседование.