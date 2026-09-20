defmodule Ste do
  @moduledoc """
  A prose linter for technical documentation: text in, violations out.

  Five mechanical rules — sentence length, passive voice, soft phrasal verbs,
  marketing adjectives and semicolons — scored over prose that an extractor has
  located in a source document. Every violation carries a line and column in the
  original file, even when the prose was three layers down.

      iex> Ste.check("The report was sent; it is seamless.")
      ...> |> Enum.map(& &1.rule)
      [:passive_voice, :semicolon, :marketing_adjective]

  ## What this is not

  It is not an implementation of ASD-STE100 or of any other published standard,
  and no conformance is claimed or implied. The rules here are re-derived from
  widely known controlled-language advice and cover a small subset of it. This
  project is not affiliated with, endorsed by, or certified by ASD or the STEMG.

  The detectors are heuristics with a deliberate false-positive rate — the
  passive-voice rule has no grammar model and over-counts by design. A single
  measurement means little; the direction between two measurements is what
  carries information.

  ## Scoring, and what lives elsewhere

  This package deliberately stops at violations. Aggregation — per-file rates,
  corpus scores, a committed floor that fails a build on regression — is the
  caller's, because every project wants a different shape and none of it needs
  to be in a library.
  """

  alias Ste.Extractor
  alias Ste.Profile
  alias Ste.Rules
  alias Ste.Span
  alias Ste.Violation

  @markdown_extensions ~w(.md .markdown)
  @elixir_extensions ~w(.ex .exs)

  @doc """
  Checks plain prose, with no markup handling.

  ## Examples

      iex> Ste.check("It is robust.") |> Enum.map(& &1.rule)
      [:marketing_adjective]
  """
  @spec check(String.t(), Profile.t()) :: [Violation.t()]
  def check(text, profile \\ Profile.new!()) when is_binary(text) do
    Rules.detect(text, profile)
  end

  @doc """
  Checks Markdown, scoring only its prose paragraphs.

  ## Options

    * `:extractor` — which `Ste.Extractor` to use. Defaults to
      `Ste.Extractor.Markdown`, the line scanner with no dependencies. Pass
      `Ste.Extractor.MDEx` for parser-backed extraction, which needs the
      optional `:mdex` dependency.

  Any remaining options are passed to the extractor.

  ## Examples

      iex> {:ok, violations} = Ste.check_markdown("# Robust\\n\\n`robust` is robust.")
      iex> Enum.map(violations, & &1.line)
      [3]
  """
  @spec check_markdown(String.t(), Profile.t(), keyword()) ::
          {:ok, [Violation.t()]} | {:error, term()}
  def check_markdown(source, profile \\ Profile.new!(), opts \\ []) when is_binary(source) do
    {extractor, extractor_opts} = Keyword.pop(opts, :extractor, Extractor.Markdown)

    with {:ok, spans} <- extractor.spans(source, extractor_opts) do
      {:ok, check_spans(spans, profile)}
    end
  end

  @doc """
  Checks the docstrings in Elixir source.

  Returns `{:error, reason}` when the source does not parse. Options are passed
  to `Ste.Extractor.Elixir.spans/2`.
  """
  @spec check_elixir(String.t(), Profile.t(), keyword()) ::
          {:ok, [Violation.t()]} | {:error, term()}
  def check_elixir(source, profile \\ Profile.new!(), opts \\ []) when is_binary(source) do
    with {:ok, spans} <- Extractor.Elixir.spans(source, opts) do
      {:ok, check_spans(spans, profile)}
    end
  end

  @doc """
  Checks a file, choosing an extractor from its extension.

  `.md` and `.markdown` use the Markdown extractor, `.ex` and `.exs` the Elixir
  one, anything else is treated as plain text. Options reach whichever extractor
  is chosen, so `extractor: Ste.Extractor.MDEx` applies to a `.md` file.
  """
  @spec check_file(Path.t(), Profile.t(), keyword()) :: {:ok, [Violation.t()]} | {:error, term()}
  def check_file(path, profile \\ Profile.new!(), opts \\ []) do
    with {:ok, source} <- File.read(path) do
      case Path.extname(path) do
        ext when ext in @markdown_extensions -> check_markdown(source, profile, opts)
        ext when ext in @elixir_extensions -> check_elixir(source, profile, opts)
        _other -> {:ok, check(source, profile)}
      end
    end
  end

  @doc """
  Checks already-extracted spans, rebasing every violation onto its span.

  This is the seam for a caller with its own extractor, or with a markup this
  package does not handle yet.
  """
  @spec check_spans([Span.t()], Profile.t()) :: [Violation.t()]
  def check_spans(spans, profile \\ Profile.new!()) when is_list(spans) do
    spans
    |> Enum.flat_map(fn %Span{} = span ->
      span.text
      |> Rules.detect(profile)
      |> Violation.rebase(span)
    end)
    |> Enum.sort_by(&{&1.line, &1.column})
  end
end
