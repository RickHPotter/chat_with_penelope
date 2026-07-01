# frozen_string_literal: true

class ChatResponseMetadata
  def prompt_metadata_for(text, prompt: nil)
    classification = MessageClassifier.classify(text)
    metadata = base_metadata(classification)

    if prompt
      metadata[:prompt_digest] = Digest::SHA256.hexdigest(prompt)
      metadata[:prompt_preview] = prompt.first(2_000)
    end

    metadata
  end

  def response_metadata(prompt_metadata, parsed_response)
    prompt_metadata.merge(
      parse_warnings: parsed_response.fetch(:parse_warnings),
      output_warnings: output_warnings_for(parsed_response)
    )
  end

  private

  def base_metadata(classification)
    {
      classifier: classification.to_h,
      prompt_builder: prompt_builder_name_for(classification),
      compact_prompt: classification.compact,
      slash_command: classification.command,
      llm_provider: Rails.configuration.chat.fetch("chat_provider"),
      llm_model: Rails.configuration.chat.fetch("chat_model")
    }
  end

  def prompt_builder_name_for(classification)
    return compact_prompt_builder_name(classification.command) if classification.compact

    {
      french_sentence: "Prompts::FrenchSentence",
      english_sentence: "Prompts::EnglishSentence",
      vocabulary: "Prompts::Vocabulary",
      grammar: "Prompts::Grammar",
      translation: "Prompts::Translation",
      conversation: "Prompts::Tutor legacy fallback"
    }.fetch(classification.intent)
  end

  def compact_prompt_builder_name(command)
    {
      "validate" => "Prompts::Compact::Validate",
      "check" => "Prompts::Compact::Validate",
      "correct" => "Prompts::Compact::Validate",
      "define" => "Prompts::Compact::Define",
      "explain" => "Prompts::Compact::Explain",
      "translate" => "Prompts::Compact::Translate",
      "say" => "Prompts::Compact::Say"
    }.fetch(command, "Prompts::Compact")
  end

  def output_warnings_for(parsed_response)
    warnings = []
    default_language = parsed_response.fetch(:default_language)
    target_language = parsed_response.fetch(:target_language)

    warnings << "target_language contains D'umas" if target_language.match?(/D'umas/i)
    warnings << "target_language contains same-language glosses" if target_language.match?(/\b(\p{L}+)\s*\(\1\)/i)
    warnings << "target_language contains same-language arrows" if target_language.match?(/([\p{L}'’ ]{3,})\s*→\s*\1/i)
    warnings << "default_language repeats translation explanation" if repeated_translation_explanation?(default_language)
    warnings << "response contains duplicate alternatives" if [ default_language, target_language ].any? { |content| duplicate_alternative?(content) }
    warnings << "response contains literal language names instead of answers" if default_language == "English" && target_language == "French"

    warnings
  end

  def duplicate_alternative?(content)
    content.scan(/['«"]([^'»"]+)['»"]\s+or\s+['«"]\1['»"]/i).any?
  end

  def repeated_translation_explanation?(content)
    translation = content[/Translation:\s*(.+)/i, 1]
    explanation = content[/Translation explanation:\s*(.+)/i, 1]

    translation.present? && explanation.present? && translation.strip == explanation.strip
  end
end
