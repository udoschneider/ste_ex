defmodule Ste.RulesTest do
  use ExUnit.Case, async: true

  alias Ste.Profile

  defp rules(text, opts) do
    text |> Ste.check(Profile.new!(opts)) |> Enum.map(& &1.rule)
  end

  describe ":long_sentence" do
    test "counts words against the cap" do
      assert rules(String.duplicate("word ", 25), rules: [:long_sentence]) == [:long_sentence]
      assert rules(String.duplicate("word ", 5), rules: [:long_sentence]) == []
    end

    test "the cap is per profile" do
      text = String.duplicate("word ", 25)
      assert rules(text, rules: [:long_sentence], sentence_cap: 30) == []
    end

    test "an abbreviation is not a sentence boundary" do
      text = "Use a value, e.g. " <> String.duplicate("word ", 25)
      assert rules(text, rules: [:long_sentence]) == [:long_sentence]
    end

    test "a decimal point is not a sentence boundary" do
      text = "Version 1.4 " <> String.duplicate("word ", 25)
      assert rules(text, rules: [:long_sentence]) == [:long_sentence]
    end

    test "genuine boundaries still split" do
      text = String.duplicate("word ", 15) <> ". " <> String.duplicate("word ", 15)
      assert rules(text, rules: [:long_sentence]) == []
    end
  end

  describe ":passive_voice" do
    test "catches regular participles" do
      assert rules("the gate is blocked", rules: [:passive_voice]) == [:passive_voice]
    end

    test "catches irregular participles the suffix pattern misses" do
      assert rules("the report was sent", rules: [:passive_voice]) == [:passive_voice]
    end

    test "sees through an adverb" do
      assert rules("the gate is silently blocked", rules: [:passive_voice]) == [:passive_voice]
    end

    test "exempts participles that read as adjectives" do
      assert rules("the schema is complicated", rules: [:passive_voice]) == []
    end

    test "the exemption list is per project" do
      opts = [rules: [:passive_voice], passive_exceptions: {:remove, ["complicated"]}]
      assert rules("the schema is complicated", opts) == [:passive_voice]
    end
  end

  describe ":phrasal_verb" do
    test "matches across arbitrary whitespace" do
      assert rules("we spin\n  up a node", rules: [:phrasal_verb]) == [:phrasal_verb]
    end

    test "is case-insensitive" do
      assert rules("Reach Out to them", rules: [:phrasal_verb]) == [:phrasal_verb]
    end

    test "respects word boundaries" do
      assert rules("a spinner upstream", rules: [:phrasal_verb]) == []
    end
  end

  describe ":marketing_adjective" do
    test "is case-insensitive and bounded" do
      assert rules("Seamless integration", rules: [:marketing_adjective]) ==
               [:marketing_adjective]

      assert rules("seamlessness is not a word we flag", rules: [:marketing_adjective]) == []
    end
  end

  describe ":semicolon" do
    test "reports each one with its column" do
      assert [first, second] = Ste.check("a; b; c", Profile.new!(rules: [:semicolon]))
      assert {first.line, first.column} == {1, 2}
      assert {second.line, second.column} == {1, 5}
    end
  end

  describe "detail" do
    test "a long sentence reports its word count and the cap it broke" do
      [violation] =
        Ste.check(String.duplicate("word ", 25), Profile.new!(rules: [:long_sentence]))

      assert violation.detail == %{words: 25, cap: 20}
    end

    test "a passive hit reports the participle that triggered it" do
      [violation] = Ste.check("it was sent", Profile.new!(rules: [:passive_voice]))
      assert violation.detail == %{participle: "sent"}
    end
  end
end
