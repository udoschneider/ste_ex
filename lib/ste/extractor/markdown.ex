defmodule Ste.Extractor.Markdown do
  @moduledoc """
  Extracts prose paragraphs from Markdown, keeping their position in the source.

  Fenced code, YAML frontmatter, headings, tables, blockquotes, list markers,
  inline code, link destinations, images, bare URLs and HTML tags are masked;
  what is left is grouped into paragraphs separated by blank lines.

  ## Why this is line-based rather than a real parser

  `earmark_parser` tracks a line number per block internally but drops it from
  the public AST, with no option to keep it, so the one pure-Elixir Markdown
  parser cannot supply the positions this module exists to preserve. The parser
  that can — `mdex`, wrapping comrak's `sourcepos` — is a Rust NIF, and pulling
  a second toolchain into every consumer is a real cost for a package whose
  whole job is reading prose.

  So this is a line scanner. Its correctness ceiling is lower than a CommonMark
  parser's: indented code blocks, lazy continuation lines and setext headings
  are not handled, and a `#` inside a fenced block is only safe because fences
  are tracked. It is enough for the documentation shapes this package targets,
  and `Ste.Extractor` exists so that swapping in a parser-backed implementation
  is one module rather than a rewrite.
  """

  @behaviour Ste.Extractor

  alias Ste.Span

  @fence ~r/^\s*(```|~~~)/u
  @heading ~r/^\s{0,3}\#{1,6}\s/u
  @table_row ~r/^\s*\|/u
  @blockquote ~r/^\s*>/u
  @list_marker ~r/^(\s*(?:[-*+]|\d+[.)])\s+)/u
  @thematic_break ~r/^\s{0,3}(?:[-*_]\s*){3,}$/u

  @inline_code ~r/`[^`]*`/u
  @image ~r/!\[[^\]]*\]\([^)]*\)/u
  @link ~r/\[([^\]]*)\]\([^)]*\)/u
  @autolink ~r/<(?:https?|mailto):[^>]*>/u
  @bare_url ~r/(?:https?:\/\/|www\.)\S+/u
  @html_tag ~r/<\/?[A-Za-z][^>]*>/u

  @doc """
  Extracts prose paragraph spans from Markdown.

  Always succeeds: a line scanner cannot reject its input. Options are accepted
  for the behaviour's sake and ignored.

  ## Examples

      iex> Ste.Extractor.Markdown.spans("# Title\\n\\nSome prose.")
      {:ok, [%Ste.Span{text: "Some prose.", line: 3, column: 1}]}
  """
  @impl Ste.Extractor
  def spans(source, _opts \\ []) when is_binary(source) do
    spans =
      source
      |> String.split("\n")
      |> mask_blocks()
      |> Enum.map(&mask_inline/1)
      |> group()

    {:ok, spans}
  end

  @spec mask_blocks([String.t()]) :: [String.t()]
  defp mask_blocks(lines) do
    {masked, _state} =
      lines
      |> Enum.with_index()
      |> Enum.map_reduce(%{fence: nil, frontmatter: :unknown}, &mask_block_line/2)

    masked
  end

  @spec mask_block_line({String.t(), non_neg_integer()}, map()) :: {String.t(), map()}
  defp mask_block_line({line, 0}, %{frontmatter: :unknown} = state) do
    if String.trim(line) == "---" do
      {blank(line), %{state | frontmatter: :open}}
    else
      mask_body_line(line, %{state | frontmatter: :closed})
    end
  end

  defp mask_block_line({line, _index}, %{frontmatter: :open} = state) do
    next = if String.trim(line) == "---", do: :closed, else: :open
    {blank(line), %{state | frontmatter: next}}
  end

  defp mask_block_line({line, _index}, %{fence: marker} = state) when is_binary(marker) do
    {blank(line), %{state | fence: if(closes?(line, marker), do: nil, else: marker)}}
  end

  defp mask_block_line({line, _index}, state), do: mask_body_line(line, state)

  @spec mask_body_line(String.t(), map()) :: {String.t(), map()}
  defp mask_body_line(line, state) do
    cond do
      match = Regex.run(@fence, line) -> {blank(line), %{state | fence: Enum.at(match, 1)}}
      masked_construct?(line) -> {blank(line), state}
      true -> {mask_list_marker(line), state}
    end
  end

  @spec masked_construct?(String.t()) :: boolean()
  defp masked_construct?(line) do
    Regex.match?(@heading, line) or Regex.match?(@table_row, line) or
      Regex.match?(@blockquote, line) or Regex.match?(@thematic_break, line)
  end

  @spec closes?(String.t(), String.t()) :: boolean()
  defp closes?(line, marker) do
    case Regex.run(@fence, line) do
      [_, ^marker] -> true
      _ -> false
    end
  end

  @spec mask_list_marker(String.t()) :: String.t()
  defp mask_list_marker(line) do
    case Regex.run(@list_marker, line) do
      [_, marker] -> blank(marker) <> String.slice(line, String.length(marker)..-1//1)
      nil -> line
    end
  end

  # Masking preserves character count, so every column after the masked run
  # still addresses the same position in the source line.
  @spec mask_inline(String.t()) :: String.t()
  defp mask_inline(line) do
    line
    |> mask(@inline_code)
    |> mask(@image)
    |> mask_link()
    |> mask(@autolink)
    |> mask(@bare_url)
    |> mask(@html_tag)
  end

  @spec mask(String.t(), Regex.t()) :: String.t()
  defp mask(text, regex) do
    Regex.replace(regex, text, fn match -> blank(match) end)
  end

  # A link's label is prose and stays; only the brackets and destination go.
  # The leading space keeps the label on the column it occupied in the source.
  @spec mask_link(String.t()) :: String.t()
  defp mask_link(text) do
    Regex.replace(@link, text, fn match, label ->
      padding = String.length(match) - String.length(label) - 1
      " " <> label <> String.duplicate(" ", max(padding, 0))
    end)
  end

  @spec blank(String.t()) :: String.t()
  defp blank(text), do: String.duplicate(" ", String.length(text))

  @spec group([String.t()]) :: [Span.t()]
  defp group(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.chunk_by(fn {line, _number} -> String.trim(line) == "" end)
    |> Enum.reject(fn [{line, _} | _] -> String.trim(line) == "" end)
    |> Enum.map(fn chunk ->
      [{_line, first_number} | _] = chunk
      Span.new(Enum.map_join(chunk, "\n", fn {line, _} -> line end), first_number, 1)
    end)
  end
end
