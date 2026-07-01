# Chat With Penelope

A local Rails app for practicing French with action-based tutor prompts, local
LLMs, streaming replies, and optional local text-to-speech.

The app is intentionally small:

- one shared conversation
- no authentication
- Hotwire for realtime updates
- TailwindCSS for styling
- PostgreSQL-backed Rails data
- Solid Queue jobs
- Solid Cable broadcasts
- Ollama or LM Studio for local model inference

## Features

- Slash-command tutor actions:
  - `/validate <French sentence>`
  - `/define <word or expression>`
  - `/explain <grammar topic or question>`
  - `/translate <text>`
  - `/say <French sentence>`
  - `/chat <message>`
- Aliases:
  - `/check` -> `/validate`
  - `/correct` -> `/validate`
- Streaming assistant responses with cancellable generation.
- Collapsible thinking/debug output when a provider emits reasoning chunks.
- English/French answer tabs for text responses.
- Copy, reprompt, cancel, and debug controls.
- Composer autocomplete for slash commands.
- Enter-to-send, with `Shift+Enter` or `Ctrl+Enter` for a line break.
- Markdown-like rendering for headings, bullets, bold text, and inline code.
- `/say` audio generation through a local TTS API.

## Slash Actions

Slash commands are the main interaction model. Each command creates an
independent prompt; previous conversation turns are not sent to the model.

That is deliberate:

- small local models behave better with compact task prompts
- old turns can pollute the current answer
- debugging is easier when each request depends only on the current input

Heuristic intent detection still exists as a compatibility path, but new prompt
work should target slash actions.

## Providers

### Ollama

Default configuration:

```bash
CHAT_PROVIDER=ollama
CHAT_API_URL=http://127.0.0.1:11434/api/generate
CHAT_MODEL=qwen3:8b
```

### LM Studio

LM Studio should run its local server on port `1234`.

Example configuration:

```bash
CHAT_PROVIDER=lm_studio
CHAT_API_URL=http://127.0.0.1:1234/v1/chat/completions
CHAT_MODEL=google/gemma-4-12b-qat
```

The app normalizes LM Studio `/v1/chat/completions` URLs to the Responses API
shape internally because `/v1/responses` supports:

```json
{ "reasoning": { "effort": "none" } }
```

LM Studio responses are requested with streaming enabled. The provider parses
Responses API SSE events and stores the raw streamed content for debugging.

## Text-To-Speech

`/say <French sentence>` generates audio instead of a normal text tutor answer.

Flow:

1. The text after `/say` is cleaned before synthesis.
2. Cleanup uses a small LLM prompt to normalize punctuation and apostrophes.
3. If cleanup parsing fails, deterministic cleanup still fixes common issues:
   backticks/curly apostrophes and obvious elisions such as `Jhabite`.
4. The app calls the local TTS API.
5. The generated WAV is written under `public/tts`.
6. The assistant message renders an audio player and download link.

Expected TTS endpoint:

```bash
curl -X POST "http://127.0.0.1:8000/synthesize" \
  -H "Content-Type: application/json" \
  -d '{
    "input_text": "Ceci est très facile maintenant !",
    "output_path": "/absolute/path/to/output.wav"
  }'
```

TTS environment variables:

```bash
TTS_API_URL=http://127.0.0.1:8000/synthesize
TTS_OPEN_TIMEOUT=5
TTS_READ_TIMEOUT=120
TTS_WRITE_TIMEOUT=30
```

If synthesis takes longer than two minutes, increase `TTS_READ_TIMEOUT`.

Important: the TTS process must be able to write to the absolute `output_path`
sent by Rails. If TTS runs in a container, mount the app's `public/tts`
directory into that container.

## Configuration

The app reads these environment variables:

```bash
CHAT_PROVIDER=ollama
CHAT_API_URL=http://127.0.0.1:11434/api/generate
CHAT_MODEL=qwen3:8b
CHAT_MAX_TOKENS=70

TTS_API_URL=http://127.0.0.1:8000/synthesize
TTS_OPEN_TIMEOUT=5
TTS_READ_TIMEOUT=120
TTS_WRITE_TIMEOUT=30
```

Use a local `.env` file during development if desired.

## Setup

```bash
bin/setup
```

Manual setup:

```bash
bundle install
bin/rails db:prepare
bin/rails db:schema:load:cable
```

Run migrations after pulling schema changes:

```bash
bin/rails db:migrate
```

## Running

Start the full development stack:

```bash
bin/dev
```

`bin/dev` starts:

- Rails web server
- Solid Queue worker
- Tailwind watcher
- JavaScript build watcher

Open:

```text
http://localhost:3000
```

If you run Rails without `bin/dev`, start the job worker separately:

```bash
bin/jobs start
```

## Realtime Notes

Development and production use Solid Cable. The cable database schema must exist
or broadcasts from Solid Queue workers will not reach the browser.

If streaming updates do not appear:

- run `bin/rails db:schema:load:cable`
- restart `bin/dev`
- make sure the Solid Queue worker is running

## Data Model

### `Chat`

The app currently uses one shared chat record.

### `Message`

Messages store:

- `role`
- `content_default_language`
- `content_target_language`
- `content_thinking`
- `raw_response`
- `prompt_metadata`
- `generation_status`
- `audio_url`

`raw_response` preserves provider output or TTS metadata for debugging.
`prompt_metadata` stores classifier, prompt, provider, and debug information.

## Architecture

- `ChatController` handles request/response coordination and Turbo Streams.
- `ChatResponder` owns message persistence, generation, streaming, parsing,
  cancellation, and TTS orchestration.
- `MessageClassifier` classifies legacy messages and slash commands.
- `CommandParser` parses explicit slash actions.
- `Prompts::Tutor` dispatches to intent-specific prompt builders.
- `Prompts::Compact::*` contains slash-action prompts.
- `LLM::Client` abstracts provider calls.
- `LLM::Providers::Ollama` supports Ollama.
- `LLM::Providers::LMStudio` supports LM Studio Responses API streaming.
- `TextToSpeech::Client` calls the local TTS API.

## Development Commands

```bash
bin/rails test
bin/rails db:migrate
bin/rails db:schema:load:cable
bin/rubocop
```

## Maintained Docs

- `docs/features/slash_intents.md`

Older prompt scratch notes were removed once their recommendations were either
implemented or superseded.
