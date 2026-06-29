# frozen_string_literal: true

class MessageClassifier
  Result = Struct.new(:intent, :normalized_text, :matched_rule, :input_excerpt, :mostly_french, :question, :lookup_mode, keyword_init: true) do
    def to_h
      {
        intent: intent.to_s,
        normalized_text:,
        matched_rule:,
        input_excerpt:,
        mostly_french:,
        question:,
        lookup_mode:
      }
    end
  end

  FRENCH_WORDS = %w[
    je tu il elle nous vous ils elles le la les un une des de du au aux est
    suis sont avec pour dans pas fatigué fatiguée veux veut viens habite
  ].freeze

  ENGLISH_QUESTION_STARTS = %w[what why how when where who].freeze
  FRENCH_QUESTION_STARTS = %w[pourquoi comment quand où qui que quoi].freeze

  def self.call(text)
    classify(text).intent
  end

  def self.classify(text)
    new(text).classify
  end

  def self.mostly_french?(text)
    new(text).mostly_french?
  end

  def initialize(text)
    @text = text.to_s.strip
    @normalized = @text.downcase.gsub(/\s+/, " ")
  end

  def intent
    classify.intent
  end

  def classify
    return result(:conversation, "blank", input_excerpt: "") if normalized.blank?

    if translation?
      result(:translation, "translation_request")
    elsif vocabulary_usage?
      result(:vocabulary, "vocabulary_usage_question", lookup_mode: "usage")
    elsif vocabulary?
      result(:vocabulary, "vocabulary_question", input_excerpt: vocabulary_expression, lookup_mode: lookup_mode_for(vocabulary_expression))
    elsif french_validation_request?
      result(:french_sentence, "french_sentence_validation_request", input_excerpt: extracted_sentence)
    elsif grammar?
      result(:grammar, "grammar_question")
    elsif french_sentence?
      result(:french_sentence, "mostly_french_statement")
    elsif english_sentence?
      result(:english_sentence, "english_statement")
    else
      result(:conversation, "fallback")
    end
  end

  private

  attr_reader :text, :normalized

  def translation?
    starts_with_any?("translate", "how do you say", "how to say")
  end

  def vocabulary?
    starts_with_any?("define", "what does", "what is") ||
      normalized.end_with?(" en français") ||
      normalized.start_with?("en français ") ||
      normalized.include?("mean") ||
      normalized.include?("signifie") ||
      normalized.include?("veut dire")
  end

  def vocabulary_usage?
    normalized.include?("what about") ||
      normalized.include?("as in") ||
      normalized.include?("wasn't") ||
      normalized.include?("wasnt") ||
      normalized.include?("doesn't") ||
      normalized.include?("doesnt")
  end

  def vocabulary_expression
    @vocabulary_expression ||= begin
      expression = normalized
        .sub(/\Adefine\s+/, "")
        .sub(/\Awhat does\s+/, "")
        .sub(/\Awhat is\s+/, "")
        .sub(/\s+mean\??\z/, "")
        .sub(/\s+en français\??\z/, "")
        .sub(/\Aen français\s+/, "")
        .sub(/\Aque veut dire\s+/, "")
        .sub(/\Aqu'?est-ce que\s+/, "")
        .sub(/\s+signifie\??\z/, "")

      expression.presence || text
    end
  end

  def lookup_mode_for(expression)
    expression.to_s.scan(/[[:alpha:]']+/).size <= 1 ? "single_word" : "expression"
  end

  def grammar?
    starts_with_any?("why", "how") ||
      normalized.include?("grammar") ||
      normalized.include?("grammatically") ||
      normalized.include?("conjugate") ||
      normalized.include?("conjugation") ||
      normalized.include?("difference") ||
      normalized.include?("pourquoi") ||
      normalized.include?("pourquoi est-ce que")
  end

  def french_validation_request?
    sentence_validation_request? && extracted_sentence.present? && MessageClassifier.mostly_french?(extracted_sentence)
  end

  def extracted_sentence
    @extracted_sentence ||= begin
      if (match = text.match(/(?:->|:)\s*(.+)\z/))
        match[1].strip
      elsif normalized.start_with?("validate ")
        text.sub(/\Avalidate\s+/i, "").strip
      elsif (match = text.match(/["“](.+?)["”]/))
        match[1].strip
      else
        ""
      end
    end
  end

  def sentence_validation_request?
    normalized.include?("grammatically correct") ||
      normalized.start_with?("validate ") ||
      normalized.include?("is this correct") ||
      normalized.include?("is it correct") ||
      normalized.include?("is this sentence correct") ||
      normalized.start_with?("correct this") ||
      normalized.start_with?("fix this")
  end

  def french_sentence?
    mostly_french? && !question?
  end

  def english_sentence?
    text.scan(/[[:alpha:]]+/).size >= 2 && !mostly_french? && !question?
  end

  public

  def mostly_french?
    normalized.match?(/[àâçéèêëîïôùûüÿœ]/) ||
      normalized.match?(/\b(?:#{Regexp.union(FRENCH_WORDS).source})\b/) ||
      normalized.match?(/\b[jldqc]'/)
  end

  private

  def question?
    normalized.end_with?("?") ||
      ENGLISH_QUESTION_STARTS.any? { |word| normalized.start_with?("#{word} ") } ||
      FRENCH_QUESTION_STARTS.any? { |word| normalized.start_with?("#{word} ") }
  end

  def starts_with_any?(*prefixes)
    prefixes.any? { |prefix| normalized.start_with?(prefix) }
  end

  def result(intent, matched_rule, input_excerpt: text, lookup_mode: nil)
    Result.new(
      intent:,
      normalized_text: normalized,
      matched_rule:,
      input_excerpt:,
      mostly_french: mostly_french?,
      question: question?,
      lookup_mode:
    )
  end
end
