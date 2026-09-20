defmodule Ste.Span do
  @moduledoc """
  A run of text together with where it starts in the source it came from.

  Spans are what makes extraction composable. An extractor never concatenates
  the prose it finds; it returns each run with its origin, so a violation found
  three layers down — inside a Markdown paragraph, inside a heredoc, inside an
  `.ex` file — still reports a position a reader can jump to.

  ## The rectangular-block invariant

  `rebase/2` assumes the base span's text is a *rectangular block*: every one of
  its lines begins at `base.column` in the enclosing source. That holds for a
  dedented heredoc and for a Markdown block, which is why both extractors can
  compose. It does **not** hold for text that starts mid-line, such as
  `@doc "some prose"`, where the first line begins at column 8 and a second line
  would begin at column 1. `Ste.Extractor.Elixir` therefore emits precise spans
  only for heredocs and degrades to attribute-line granularity otherwise, rather
  than reporting a confidently wrong column.
  """

  @type t :: %__MODULE__{text: String.t(), line: pos_integer(), column: pos_integer()}

  defstruct text: "", line: 1, column: 1

  @doc """
  Builds a span.

  ## Examples

      iex> Ste.Span.new("hello", 3, 5)
      %Ste.Span{text: "hello", line: 3, column: 5}
  """
  @spec new(String.t(), pos_integer(), pos_integer()) :: t()
  def new(text, line \\ 1, column \\ 1) when is_binary(text) do
    %__MODULE__{text: text, line: line, column: column}
  end

  @doc """
  Re-expresses spans extracted from `base.text` in `base`'s own coordinate system.

  See the module documentation for the invariant this relies on.

  ## Examples

      iex> base = Ste.Span.new("a\\nb", 10, 3)
      iex> inner = [Ste.Span.new("a", 1, 1), Ste.Span.new("b", 2, 1)]
      iex> Ste.Span.rebase(inner, base)
      [%Ste.Span{text: "a", line: 10, column: 3}, %Ste.Span{text: "b", line: 11, column: 3}]
  """
  @spec rebase([t()], t()) :: [t()]
  def rebase(spans, %__MODULE__{} = base) when is_list(spans) do
    Enum.map(spans, fn %__MODULE__{} = span ->
      %__MODULE__{
        span
        | line: base.line + span.line - 1,
          column: base.column + span.column - 1
      }
    end)
  end

  @doc """
  Converts a byte offset into `text` to a `{line, column}` pair, both 1-based.

  Columns are counted in codepoints, matching `Code.string_to_quoted/2`.

  ## Examples

      iex> Ste.Span.position("ab\\ncd", 3)
      {2, 1}
  """
  @spec position(String.t(), non_neg_integer()) :: {pos_integer(), pos_integer()}
  def position(text, byte_offset) when is_binary(text) and byte_offset >= 0 do
    prefix = binary_part(text, 0, min(byte_offset, byte_size(text)))
    lines = String.split(prefix, "\n")
    {length(lines), lines |> List.last() |> String.length() |> Kernel.+(1)}
  end
end
