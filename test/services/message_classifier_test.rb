# frozen_string_literal: true

require "test_helper"

class MessageClassifierTest < ActiveSupport::TestCase
  test "classifies vocabulary questions" do
    assert_equal :vocabulary, MessageClassifier.call("Define fatiguée.")
    assert_equal :vocabulary, MessageClassifier.call("What does comprendre mean?")
    assert_equal :vocabulary, MessageClassifier.call("Que veut dire pourtant ?")
  end

  test "classifies grammar questions" do
    assert_equal :grammar, MessageClassifier.call('Why is it "je me couche"?')
    assert_equal :grammar, MessageClassifier.call("Difference between que and quoi?")
  end

  test "classifies French sentence validation requests as French sentences" do
    classification = MessageClassifier.classify("is this grammatically correct? -> J'habite en rue Dumas")

    assert_equal :french_sentence, classification.intent
    assert_equal "french_sentence_validation_request", classification.matched_rule
    assert_equal "J'habite en rue Dumas", classification.input_excerpt
  end

  test "classifies validate French sentence requests as French sentences" do
    classification = MessageClassifier.classify("validate C'est la correct rue?")

    assert_equal :french_sentence, classification.intent
    assert_equal "french_sentence_validation_request", classification.matched_rule
    assert_equal "C'est la correct rue?", classification.input_excerpt
  end

  test "classifies English word in French lookup as single word vocabulary" do
    classification = MessageClassifier.classify("straight en français")

    assert_equal :vocabulary, classification.intent
    assert_equal "straight", classification.input_excerpt
    assert_equal "single_word", classification.lookup_mode
  end

  test "classifies follow-up usage questions as vocabulary usage" do
    classification = MessageClassifier.classify("wasnt droit the translation for right? what about straight as in going straight in the street")

    assert_equal :vocabulary, classification.intent
    assert_equal "vocabulary_usage_question", classification.matched_rule
    assert_equal "usage", classification.lookup_mode
  end

  test "classifies translation requests" do
    assert_equal :translation, MessageClassifier.call("Translate je suis fatigué")
    assert_equal :translation, MessageClassifier.call("How do you say I am tired?")
  end

  test "classifies French sentences" do
    assert_equal :french_sentence, MessageClassifier.call("Je suis fatigué.")
    assert_equal :french_sentence, MessageClassifier.call("J'habite rue Dumas.")
  end

  test "classifies English sentences" do
    assert_equal :english_sentence, MessageClassifier.call("I am tired.")
    assert_equal :english_sentence, MessageClassifier.call("I want a clean room.")
  end

  test "classifies conversation fallback" do
    assert_equal :conversation, MessageClassifier.call("Hi")
  end
end
