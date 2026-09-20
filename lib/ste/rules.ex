defmodule Ste.Rules do
  @moduledoc """
  The five mechanical detectors.

  Each returns violations positioned relative to the text it was given.
  `Ste.check_spans/2` rebases them onto the source.

  ## What these are and are not

  They are a re-derived subset of well-known controlled-language advice, chosen
  because each one is *countable* without a parser. They are not an
  implementation of any published standard, and they carry a deliberate
  false-positive rate — the passive detector has no grammar model and will
  over-count. Treat the output as a signal, not a verdict.
  """

  alias Ste.Profile
  alias Ste.Span
  alias Ste.Violation

  @be_verbs ~w(is are was were be been being am)

  @abbreviations ~w(
    e.g. i.e. etc. vs. cf. al. approx. incl. no. fig. eq. ca.
    mr. mrs. ms. dr. prof. st. jr. sr. inc. ltd. co.
  )

  @doc """
  Runs every rule enabled in `profile` against `text`.

  Positions are relative to `text`, 1-based.
  """
  @spec detect(String.t(), Profile.t()) :: [Violation.t()]
  def detect(text, %Profile{} = profile) when is_binary(text) do
    profile.rules
    |> Enum.flat_map(&detect_rule(&1, text, profile))
    |> Enum.sort_by(&{&1.line, &1.column})
  end

  @spec detect_rule(Violation.rule(), String.t(), Profile.t()) :: [Violation.t()]
  defp detect_rule(:semicolon, text, _profile) do
    matches(~r/;/u, text, :semicolon, fn _match, _captures -> %{} end)
  end

  defp detect_rule(:marketing_adjective, text, profile) do
    case term_regex(profile.marketing_adjectives) do
      nil ->
        []

      regex ->
        matches(regex, text, :marketing_adjective, fn _match, _captures -> %{} end)
    end
  end

  defp detect_rule(:phrasal_verb, text, profile) do
    case term_regex(profile.phrasal_verbs) do
      nil ->
        []

      regex ->
        matches(regex, text, :phrasal_verb, fn _match, _captures -> %{} end)
    end
  end

  defp detect_rule(:passive_voice, text, profile) do
    regex = ~r/\b(?:#{Enum.join(@be_verbs, "|")})\s+(?:\w+ly\s+)?(\w+)\b/iu

    regex
    |> matches(text, :passive_voice, fn _match, [participle] -> %{participle: participle} end)
    |> Enum.filter(&passive?(&1.detail.participle, profile))
  end

  defp detect_rule(:long_sentence, text, profile) do
    text
    |> sentences()
    |> Enum.flat_map(fn {offset, sentence} ->
      words = word_count(sentence)

      if words > profile.sentence_cap do
        {line, column} = Span.position(text, offset)

        [
          %Violation{
            rule: :long_sentence,
            line: line,
            column: column,
            text: String.trim(sentence),
            detail: %{words: words, cap: profile.sentence_cap}
          }
        ]
      else
        []
      end
    end)
  end

  @spec passive?(String.t(), Profile.t()) :: boolean()
  defp passive?(participle, profile) do
    word = String.downcase(participle)

    cond do
      word in Enum.map(profile.passive_exceptions, &String.downcase/1) -> false
      word in Enum.map(profile.irregular_participles, &String.downcase/1) -> true
      String.ends_with?(word, ["ed", "en"]) -> true
      true -> false
    end
  end

  @spec term_regex([String.t()]) :: Regex.t() | nil
  defp term_regex([]), do: nil

  defp term_regex(terms) do
    alternation =
      terms
      |> Enum.sort_by(&(-String.length(&1)))
      |> Enum.map_join("|", fn term ->
        term
        |> String.split(~r/\s+/u, trim: true)
        |> Enum.map_join("\\s+", &Regex.escape/1)
      end)

    Regex.compile!("\\b(?:#{alternation})\\b", "iu")
  end

  @spec matches(Regex.t(), String.t(), Violation.rule(), (String.t(), [String.t()] -> map())) ::
          [Violation.t()]
  defp matches(regex, text, rule, detail_fun) do
    regex
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{offset, length} | capture_indexes] ->
      {line, column} = Span.position(text, offset)
      matched = binary_part(text, offset, length)
      captures = Enum.map(capture_indexes, fn {o, l} -> binary_part(text, o, l) end)

      %Violation{
        rule: rule,
        line: line,
        column: column,
        text: matched,
        detail: detail_fun.(matched, captures)
      }
    end)
  end

  @spec sentences(String.t()) :: [{non_neg_integer(), String.t()}]
  defp sentences(text) do
    boundaries = Regex.scan(~r/(?<=[.!?])\s+/u, text, return: :index)

    {chunks, last_start} =
      Enum.reduce(boundaries, {[], 0}, fn [{offset, length}], {acc, start} ->
        {[{start, binary_part(text, start, offset - start)} | acc], offset + length}
      end)

    remainder = binary_part(text, last_start, byte_size(text) - last_start)

    [{last_start, remainder} | chunks]
    |> Enum.reverse()
    |> Enum.reject(fn {_offset, chunk} -> String.trim(chunk) == "" end)
    |> merge_abbreviations()
  end

  # A terminator preceded by a known abbreviation or a digit is not a sentence
  # boundary. Without this, "see e.g. the table" and "version 1.4 shipped" each
  # split into two short sentences and hide a genuinely long one.
  @spec merge_abbreviations([{non_neg_integer(), String.t()}]) :: [
          {non_neg_integer(), String.t()}
        ]
  defp merge_abbreviations(chunks) do
    chunks
    |> Enum.reduce([], &merge_chunk/2)
    |> Enum.reverse()
  end

  @spec merge_chunk({non_neg_integer(), String.t()}, [{non_neg_integer(), String.t()}]) ::
          [{non_neg_integer(), String.t()}]
  defp merge_chunk(chunk, []), do: [chunk]

  defp merge_chunk({offset, chunk}, [{prev_offset, prev} | rest] = acc) do
    if false_boundary?(prev) do
      [{prev_offset, binary_part_between(prev_offset, offset, prev, chunk)} | rest]
    else
      [{offset, chunk} | acc]
    end
  end

  @spec false_boundary?(String.t()) :: boolean()
  defp false_boundary?(chunk) do
    trimmed = String.trim_trailing(chunk)
    last = trimmed |> String.split(~r/\s+/u, trim: true) |> List.last() || ""

    String.downcase(last) in @abbreviations or Regex.match?(~r/\d\.$/u, trimmed)
  end

  @spec binary_part_between(non_neg_integer(), non_neg_integer(), String.t(), String.t()) ::
          String.t()
  defp binary_part_between(prev_offset, offset, prev, chunk) do
    gap = String.duplicate(" ", max(offset - prev_offset - byte_size(prev), 0))
    prev <> gap <> chunk
  end

  @spec word_count(String.t()) :: non_neg_integer()
  defp word_count(sentence) do
    sentence
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reject(&(&1 =~ ~r/^\W+$/u))
    |> length()
  end
end
