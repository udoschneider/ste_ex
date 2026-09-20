defmodule Ste.Extractor.Text do
  @moduledoc """
  The identity extractor: the whole input is prose.

  Useful on its own for commit messages, error strings and CLI output, and as
  the base case when a caller has already done its own extraction.
  """

  @behaviour Ste.Extractor

  alias Ste.Span

  @doc """
  Returns the whole input as a single span at line 1, column 1.

  ## Examples

      iex> Ste.Extractor.Text.spans("prose")
      {:ok, [%Ste.Span{text: "prose", line: 1, column: 1}]}
  """
  @impl Ste.Extractor
  def spans(source, _opts \\ []) when is_binary(source) do
    {:ok, [Span.new(source, 1, 1)]}
  end
end
