# Slash Intents

## Goal

Add explicit Telegram-style commands so learners can trigger action-based QA
with compact prompts.

This is primarily for smaller local models such as LM Studio models, where long
prompts and ambiguous routing increase malformed JSON and repetitive answers.

## Commands

Initial commands:

- `/validate <French sentence>`: validate and correct a French sentence.
- `/define <word or expression>`: explain vocabulary.
- `/explain <grammar topic or question>`: explain grammar.
- `/translate <text>`: translate explicitly.
- `/say <English sentence>`: translate an English sentence naturally into French.
- `/chat <message>`: general tutor conversation fallback.

Aliases:

- `/check` -> `/validate`
- `/correct` -> `/validate`

## Routing

Slash commands are the default interaction model.

If a message starts with a known slash command:

- set `matched_rule` to `slash_command`
- set `compact` to `true`
- use the command body as `input_excerpt`
- route to a compact prompt builder

Heuristic classification remains available only as a legacy compatibility path.
New prompt and model tuning work should target slash-command actions first.

## Independence Policy

Each action prompt is independent.

The app does not send previous conversation turns to the model when generating a
new answer or regenerating an existing answer.

Reason:

- slash commands should behave like explicit actions, not open-ended chat
- smaller local models are more reliable with less prompt context
- old turns can pollute the current task and cause repetition or malformed JSON
- debugging is easier when each request depends only on the current command input

Implementation status:

- `ChatResponder` builds prompts with `messages: []`

## Prompt Strategy

Compact prompts should:

- be significantly shorter than the heuristic prompts
- keep the same JSON contract
- include only the task-specific instructions
- avoid optional sections unless needed
- repeat the exact JSON key names at the end
- be independent; do not include conversation history

The response contract remains:

```json
{
  "default_language": "complete answer written in English",
  "target_language": "complete answer written in French"
}
```

Do not use placeholder-only examples in compact prompts. Small models may copy
placeholders literally. Compact prompts should include bad/good examples.

## Status

- [x] Planning documented.
- [x] Slash command parser added.
- [x] Slash commands routed before heuristics.
- [x] Compact prompt builders added.
- [x] Metadata records command and compact prompt usage.
- [x] Tests added.
- [x] Placeholder-only JSON examples removed from compact prompts.
- [x] Prompt generation made independent from conversation history.

## Open Questions

- Whether to enforce slash commands in the UI composer.
- Whether to add structured response sections later.
- Whether LM Studio should use JSON schema mode once its exact supported schema
  shape is verified.
