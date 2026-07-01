# frozen_string_literal: true

class ChatAudioResponder
  def initialize(responder:, client:, tts_client:)
    @responder = responder
    @client = client
    @tts_client = tts_client
  end

  def call(assistant_message:, user_message:)
    prompt_metadata = responder.prompt_metadata_for(user_message).merge(
      prompt_builder: "TextToSpeech::Client",
      audio_generation: true
    )
    source_text = CommandParser.call(user_message).input.presence || user_message.to_s
    cleaned_text = clean_speech_text(source_text)
    tts_result = synthesize(assistant_message, cleaned_text)

    complete_audio_message(assistant_message, prompt_metadata, source_text, cleaned_text, tts_result)
  rescue TextToSpeech::Error, LLM::Errors::Error => e
    failed_audio_message(assistant_message, user_message, e)
  end

  private

  attr_reader :responder, :client, :tts_client

  def clean_speech_text(source_text)
    llm_cleaned_text(source_text).presence || deterministic_speech_cleanup(source_text)
  end

  def llm_cleaned_text(source_text)
    raw_response = client.generate(prompt: speech_cleanup_prompt(source_text))
    parsed = responder.parse_structured_response(raw_response)
    deterministic_speech_cleanup(parsed.fetch(:target_language))
  rescue LLM::Errors::Error
    nil
  end

  def synthesize(assistant_message, cleaned_text)
    tts_client.synthesize(
      input_text: cleaned_text,
      output_basename: "message_#{assistant_message.id}.wav"
    )
  end

  def complete_audio_message(assistant_message, prompt_metadata, source_text, cleaned_text, tts_result)
    assistant_message.update!(
      content_default_language: "",
      content_target_language: audio_message_content(cleaned_text),
      audio_url: tts_result.audio_url,
      generation_status: "complete",
      raw_response: raw_response_for(cleaned_text, tts_result),
      prompt_metadata: audio_metadata(prompt_metadata, source_text, cleaned_text, tts_result)
    )
    responder.broadcast_message(assistant_message)
    assistant_message
  end

  def failed_audio_message(assistant_message, user_message, error)
    assistant_message.update!(
      content_default_language: "Audio generation failed: #{error.message}",
      content_target_language: "La génération audio a échoué : #{error.message}",
      generation_status: "complete",
      raw_response: { error: error.class.name, message: error.message }.to_json,
      prompt_metadata: responder.prompt_metadata_for(user_message).merge(
        audio_generation: true,
        output_warnings: [ "audio generation failed" ]
      )
    )
    responder.broadcast_message(assistant_message)
    assistant_message
  end

  def raw_response_for(cleaned_text, tts_result)
    {
      response: cleaned_text,
      tts: {
        input_text: tts_result.input_text,
        output_path: tts_result.output_path,
        audio_url: tts_result.audio_url,
        response_body: tts_result.response_body
      }
    }.to_json
  end

  def audio_metadata(prompt_metadata, source_text, cleaned_text, tts_result)
    prompt_metadata.merge(
      tts_input_text: cleaned_text,
      tts_audio_url: tts_result.audio_url,
      output_warnings: cleanup_warnings(source_text, cleaned_text)
    )
  end

  def speech_cleanup_prompt(source_text)
    <<~PROMPT
      You clean French text before text-to-speech.

      Return exactly one valid JSON object with:
      {
        "default_language": "",
        "target_language": "cleaned French sentence"
      }

      Rules:
      - Keep the same meaning.
      - Do not translate.
      - Fix apostrophes and obvious spacing only.
      - Use normal apostrophe `'`, never backtick `.
      - Fix common elisions like `Jhabite` to `J'habite` when obvious.
      - Do not add explanations.

      Text:
      #{source_text}
    PROMPT
  end

  def deterministic_speech_cleanup(text)
    cleaned = text.to_s.strip.tr("`´’‘", "'")
    cleaned = cleaned.gsub(/\s+/, " ")
    cleaned = cleaned.gsub(/\b([Jj])(?=ai|aime|adore|arrive|attends|ouvre|habite|emprunte|étais|etais|écoute|ecoute)/, "\\1'")
    cleaned.gsub(/\b([CcDdLlMmNnQqSsTt])\s+'/, "\\1'")
  end

  def audio_message_content(cleaned_text)
    <<~TEXT.strip
      # Audio
      #{cleaned_text}
    TEXT
  end

  def cleanup_warnings(source_text, cleaned_text)
    return [] if source_text == cleaned_text

    [ "speech text cleaned before TTS" ]
  end
end
