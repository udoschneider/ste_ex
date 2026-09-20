defmodule Ste.Extractor do
  @moduledoc """
  Turns a source document into the prose spans worth scoring.

  An extractor answers one question — *which parts of this file are prose, and
  where are they?* — and answers it without concatenating, so positions survive.

  ## The masking rule

  Implementations replace non-prose with spaces rather than deleting it. A
  fenced code block becomes blank lines of the same length; an inline code run
  becomes the same number of spaces. Deleting would shift every column after the
  cut and make the reported position wrong in exactly the files that need it
  most. Masking costs nothing and keeps each extracted block rectangular, which
  is what `Ste.Span.rebase/2` relies on.
  """

  alias Ste.Span

  @doc """
  Extracts prose spans from `source`.

  Positions are relative to `source`, 1-based.
  """
  @callback spans(source :: String.t(), opts :: keyword()) ::
              {:ok, [Span.t()]} | {:error, term()}
end
