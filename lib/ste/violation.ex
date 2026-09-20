defmodule Ste.Violation do
  @moduledoc """
  One rule breach, located in the source it was found in.

  After `Ste.check_spans/2`, `line` and `column` are rebased through every
  extraction layer, so they address the original file rather than an
  intermediate string.
  """

  alias Ste.Span

  @type rule ::
          :long_sentence
          | :passive_voice
          | :phrasal_verb
          | :marketing_adjective
          | :semicolon

  @type t :: %__MODULE__{
          rule: rule() | nil,
          line: pos_integer(),
          column: pos_integer(),
          text: String.t(),
          detail: map()
        }

  defstruct [:rule, :text, line: 1, column: 1, detail: %{}]

  @doc """
  Re-expresses violations found in `span.text` in `span`'s coordinate system.

  Mirrors `Ste.Span.rebase/2` and relies on the same rectangular-block invariant.

  ## Examples

      iex> violation = %Ste.Violation{rule: :semicolon, line: 2, column: 4, text: ";"}
      iex> [rebased] = Ste.Violation.rebase([violation], Ste.Span.new("…", 10, 3))
      iex> {rebased.line, rebased.column}
      {11, 6}
  """
  @spec rebase([t()], Span.t()) :: [t()]
  def rebase(violations, %Span{} = span) when is_list(violations) do
    Enum.map(violations, fn %__MODULE__{} = violation ->
      %__MODULE__{
        violation
        | line: span.line + violation.line - 1,
          column: span.column + violation.column - 1
      }
    end)
  end
end
