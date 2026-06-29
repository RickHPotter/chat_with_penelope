# Chat With Penelope

A local Rails chatbot for practicing French with local LLM providers.

The app is intentionally small:

- one shared conversation
- no authentication
- no chat history UI
- Hotwire for updates
- TailwindCSS for styling
- Ollama or LM Studio for local model inference

## What It Does

- Accepts a single shared stream of messages
- Sends user input to a local Ollama instance
- Stores both the raw model response and the parsed assistant reply
- Shows assistant responses in English and French
- Lets you toggle between the two languages without another request
- Lets you copy the currently visible language
- Lets you reprompt an assistant message in place

## Tech Stack

- Ruby on Rails 8.1
- Hotwire (Turbo + Stimulus)
- TailwindCSS
- PostgreSQL
- Solid Queue
- Solid Cable
- Solid Cache
- Ollama or LM Studio

## Requirements

- Ruby
- Bundler
- PostgreSQL
- Ollama running locally

## Configuration

The app reads these environment variables:

- `CHAT_API_URL`
- `CHAT_MODEL`
- `CHAT_PROVIDER`

Defaults:

- `CHAT_PROVIDER=ollama`
- `CHAT_API_URL=http://127.0.0.1:11434/api/generate`
- `CHAT_MODEL=qwen3:8b`

For LM Studio's OpenAI-compatible local server, use:

- `CHAT_PROVIDER=lm_studio`
- `CHAT_API_URL=http://127.0.0.1:1234/v1/chat/completions`
- `CHAT_MODEL=frenchgemma-3-4b-instruct`

The local `.env` file can be used during development.

## Setup

```bash
bin/setup
```

If you prefer to do it manually:

```bash
bundle install
bin/rails db:prepare
```

## Running The App

Start the full development stack:

```bash
bin/dev
```

This starts the web server and the job worker defined in `Procfile.dev`.

If you want to run the worker separately:

```bash
bin/jobs start
```

Open the app at:

```text
http://localhost:3001
```

## Local LLM Provider

The chatbot expects the configured local provider to be running and reachable at the configured API URL.

For Ollama defaults, make sure Ollama is available at:

```text
http://127.0.0.1:11434
```

For LM Studio, start the local server and make sure the OpenAI-compatible endpoint is available at:

```text
http://127.0.0.1:1234/v1/chat/completions
```

The app sends structured JSON prompts and expects a JSON response with:

- `default_language`
- `target_language`

The raw response is preserved in the database as `raw_response`.

## App Behavior

### Messages

- User messages are stored as plain chat messages
- Assistant messages store:
  - English content in `content_default_language`
  - French content in `content_target_language`
  - the untouched model output in `raw_response`

### Assistant Actions

Each assistant message includes:

- `Copy`
- `Reprompt`

`Copy` copies the currently visible language only.

`Reprompt` regenerates that message in place using the conversation up to, but not including, the assistant message being regenerated.

### Error Handling

The app tries to fail gracefully when Ollama is unavailable, times out, or returns malformed JSON. Friendly errors are shown inside the chat instead of crashing the page.

## Architecture Notes

- `ChatController` stays thin and only coordinates requests and Turbo Streams
- `ChatResponder` owns message persistence, prompt building, response parsing, and regeneration
- `Prompts::Tutor` owns the system prompt
- `LLM::Client` is the app-facing abstraction for model generation
- `LLM::Providers::Ollama` supports Ollama `/api/generate`
- `LLM::Providers::LMStudio` supports LM Studio's OpenAI-compatible `/v1/chat/completions`

That separation makes it easier to add future providers later without changing the rest of the chat flow.

## Data Model

### `Chat`

The app uses one shared chat record. The model is already structured so multiple chats can be added later if needed.

### `Message`

Messages store:

- `role`
- `content_default_language`
- `content_target_language`
- `raw_response`

## Development Commands

```bash
bin/rails test
bin/rubocop
bin/rails db:migrate
bin/rails db:seed
```

## Notes

This project is an MVP. It is designed to stay simple now while leaving room for:

- multiple providers
- streaming
- text-to-speech
- long-term tutoring memory
- richer assistant message formats
