defmodule Ste.Extractor.Elixir do
  @moduledoc """
  Extracts `@moduledoc`, `@doc` and `@typedoc` prose from Elixir source.

  Uses `Code.string_to_quoted/2` only — no dependency, and the literal metadata
  carries everything needed to place a docstring precisely:

      [delimiter: "\\"\\"\\"", indentation: 2, line: 2, column: 14]

  Elixir dedents a heredoc when it builds the string, so content begins one line
  below the opening delimiter at `indentation + 1`. That is a rectangular block,
  which is exactly what `Ste.Span.rebase/2` needs.

  ## Docstrings are Markdown

  A docstring is Markdown, and most well-documented modules are mostly doctests.
  Scoring one as raw text means scoring `iex>` blocks and `## Examples` headings
  as prose, which is noise rather than signal, so this extractor runs
  `Ste.Extractor.Markdown` over each docstring by default. Pass
  `markdown: false` for the rare caller that wants the raw text.

  ## Where precision degrades

  Only heredocs get exact positions. A single-line `@doc "…"` is reported at the
  attribute's own line and the column just inside the quote, which is right
  until an escape sequence appears — `\\n` is two characters in the source and one
  in the parsed value, so every column after it would be wrong. Rather than
  report a confident wrong column, the line is the guarantee and the column is
  best effort. Interpolated docstrings are skipped: they are not string
  literals, so there is no single run of text to place.
  """

  @behaviour Ste.Extractor

  alias Ste.Extractor.Markdown
  alias Ste.Span

  @attributes [:moduledoc, :doc, :typedoc]

  @doc """
  Extracts docstring spans from Elixir source.

  ## Options

    * `:markdown` — how to treat the docstring's Markdown. `true` (the default)
      uses `Ste.Extractor.Markdown`, `false` scores the raw text, and a module
      name uses that extractor — `markdown: Ste.Extractor.MDEx`, for instance.
      See the module documentation for why the default is not `false`.

  Returns `{:error, reason}` from `Code.string_to_quoted/2` when the source does
  not parse.

  ## Examples

      iex> Ste.Extractor.Elixir.spans(~s|defmodule D do\\n  @doc "prose"\\n  def f, do: :ok\\nend|)
      {:ok, [%Ste.Span{text: "prose", line: 2, column: 9}]}
  """
  @impl Ste.Extractor
  def spans(source, opts \\ []) when is_binary(source) do
    with {:ok, ast} <- parse(source) do
      ast
      |> docstrings()
      |> expand_all(markdown_extractor(Keyword.get(opts, :markdown, true)))
    end
  end

  @spec markdown_extractor(boolean() | module()) :: module() | false
  defp markdown_extractor(false), do: false
  defp markdown_extractor(true), do: Markdown
  defp markdown_extractor(module) when is_atom(module), do: module

  @spec parse(String.t()) :: {:ok, Macro.t()} | {:error, term()}
  defp parse(source) do
    Code.string_to_quoted(source,
      columns: true,
      token_metadata: true,
      literal_encoder: &{:ok, {:__block__, &2, [&1]}}
    )
  end

  @spec docstrings(Macro.t()) :: [Span.t()]
  defp docstrings(ast) do
    {_ast, spans} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{attribute, _, [{:__block__, meta, [text]}]}]} = node, acc
        when attribute in @attributes and is_binary(text) ->
          {node, [span(text, meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(spans)
  end

  @spec span(String.t(), keyword()) :: Span.t()
  defp span(text, meta) do
    if heredoc?(meta) do
      Span.new(text, meta[:line] + 1, Keyword.get(meta, :indentation, 0) + 1)
    else
      Span.new(text, meta[:line], Keyword.get(meta, :column, 0) + 1)
    end
  end

  @spec heredoc?(keyword()) :: boolean()
  defp heredoc?(meta), do: Keyword.get(meta, :delimiter) in [~s("""), ~s(''')]

  @spec expand_all([Span.t()], module() | false) :: {:ok, [Span.t()]} | {:error, term()}
  defp expand_all(spans, false), do: {:ok, spans}

  defp expand_all(spans, extractor) do
    Enum.reduce_while(spans, {:ok, []}, fn span, {:ok, acc} ->
      # A pluggable extractor can genuinely fail -- Ste.Extractor.MDEx reports a
      # missing optional dependency here -- so this propagates rather than
      # asserting, which is what the line scanner alone allowed.
      case extractor.spans(span.text, []) do
        {:ok, inner} -> {:cont, {:ok, acc ++ Span.rebase(inner, span)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
