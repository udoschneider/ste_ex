defmodule Ste.Extractor.MDEx do
  @moduledoc """
  Extracts prose from Markdown with a real CommonMark parser.

  Requires the optional `:mdex` dependency:

      def deps do
        [{:ste, "~> 0.1"}, {:mdex, "~> 0.13"}]
      end

  Without it, `spans/2` returns `{:error, {:missing_dependency, :mdex}}` rather
  than silently falling back — the same input must not score differently
  depending on what happens to be installed.

  ## Why both this and `Ste.Extractor.Markdown`

  `Ste.Extractor.Markdown` is a line scanner with no dependencies. This module is
  more correct and costs a Rust NIF plus five transitive dependencies. Neither
  answer is right for every project, so both exist and the caller picks.

  What the parser gets right that the scanner cannot:

    * **Setext headings** (`Title` underlined with `===`) — invisible to a
      scanner looking for a leading `#`.
    * **Indented code blocks** — four-space indentation is a code fence the
      scanner has no state for.
    * **Tables** — parsed as tables rather than recognised by a leading pipe.
    * **Link destinations** — a structural attribute, not a run of characters to
      mask, so the label stays prose and the URL is never scored.
    * **Exact inline positions** — every run of prose carries its own
      coordinates, so text on either side of an inline code span is placed
      exactly rather than approximated.

  ## Grouping, and why it is not one span per node

  The parser emits a separate text node per source line, split on soft breaks.
  Scoring those individually would cut every sentence that wraps, and sentence
  length is one of the five rules.

  So the text nodes of a paragraph are rebuilt into a single span, with each run
  padded to its true column and excluded inline content (code, link
  destinations, images, autolinks) left as gaps. The result is a rectangular
  block anchored at the paragraph's first line and its leftmost column, which is
  what `Ste.Span.rebase/2` needs — and every character inside it sits where the
  source puts it.
  """

  @behaviour Ste.Extractor

  @compile {:no_warn_undefined, MDEx}

  alias Ste.Span

  # Containers whose contents are not prose this package rewrites. Compared as
  # atoms rather than matched as structs, so this module still compiles when the
  # optional dependency is absent.
  @skipped [
    MDEx.BlockQuote,
    MDEx.Code,
    MDEx.CodeBlock,
    MDEx.FootnoteReference,
    MDEx.FrontMatter,
    MDEx.Heading,
    MDEx.HtmlBlock,
    MDEx.HtmlInline,
    MDEx.Image,
    MDEx.Math,
    MDEx.MultilineBlockQuote,
    MDEx.Raw,
    MDEx.Table,
    MDEx.ThematicBreak
  ]

  @paragraph MDEx.Paragraph
  @text MDEx.Text
  @link MDEx.Link

  @default_extension [
    front_matter_delimiter: "---",
    autolink: true,
    table: true,
    strikethrough: true,
    tasklist: true,
    footnotes: true
  ]

  @doc """
  Extracts prose spans from Markdown.

  ## Options

    * `:extension` — merged over the default CommonMark extensions. Tables and
      autolinks are enabled by default because without them a pipe row and a
      bare URL both arrive as ordinary prose.

  Returns `{:error, {:missing_dependency, :mdex}}` when the optional dependency
  is not installed, or `{:error, reason}` when the parser rejects the input.
  """
  @impl Ste.Extractor
  def spans(source, opts \\ []) when is_binary(source) do
    if Code.ensure_loaded?(MDEx) do
      parse(source, opts)
    else
      {:error, {:missing_dependency, :mdex}}
    end
  end

  @doc "The CommonMark extensions enabled unless a caller overrides them."
  @spec default_extension() :: keyword()
  def default_extension, do: @default_extension

  @spec parse(String.t(), keyword()) :: {:ok, [Span.t()]} | {:error, term()}
  defp parse(source, opts) do
    extension = Keyword.merge(@default_extension, Keyword.get(opts, :extension, []))

    case MDEx.parse_document(source, extension: extension) do
      {:ok, document} -> {:ok, collect(Map.get(document, :nodes, []))}
      {:error, reason} -> {:error, {:parse_failed, reason}}
    end
  end

  @spec collect([struct()]) :: [Span.t()]
  defp collect(nodes), do: Enum.flat_map(nodes, &collect_node/1)

  @spec collect_node(struct()) :: [Span.t()]
  defp collect_node(%{__struct__: struct} = node) do
    cond do
      struct in @skipped -> []
      struct == @paragraph -> node |> Map.get(:nodes) |> inline_texts() |> build_span()
      true -> node |> Map.get(:nodes) |> List.wrap() |> collect()
    end
  end

  defp collect_node(_node), do: []

  # Descends inline containers -- emphasis, strong, links -- gathering the text
  # runs that count as prose. Everything in @skipped is dropped here too, so an
  # inline code span leaves a gap rather than a scored word.
  @spec inline_texts([struct()] | nil) :: [struct()]
  defp inline_texts(nodes) do
    nodes
    |> List.wrap()
    |> Enum.flat_map(fn
      %{__struct__: struct} = node ->
        cond do
          struct in @skipped -> []
          struct == @link and autolink?(node) -> []
          struct == @text -> [node]
          true -> node |> Map.get(:nodes) |> inline_texts()
        end

      _other ->
        []
    end)
  end

  # A bare URL becomes a link whose label is the URL itself. That is a
  # destination wearing a label's clothes, and scoring it would count the host
  # and path as words.
  @spec autolink?(struct()) :: boolean()
  defp autolink?(node) do
    case node |> Map.get(:nodes) |> List.wrap() do
      [%{__struct__: @text, literal: literal}] -> literal == Map.get(node, :url)
      _other -> false
    end
  end

  @spec build_span([struct()]) :: [Span.t()]
  defp build_span([]), do: []

  defp build_span([first | _] = texts) do
    {base_line, _} = start_of(first)
    base_column = texts |> Enum.map(&elem(start_of(&1), 1)) |> Enum.min()

    {buffer, _cursor} =
      Enum.reduce(texts, {[], {base_line, base_column}}, fn text, {acc, cursor} ->
        place(text, acc, cursor, base_column)
      end)

    [Span.new(IO.iodata_to_binary(buffer), base_line, base_column)]
  end

  @spec place(struct(), iodata(), {pos_integer(), pos_integer()}, pos_integer()) ::
          {iodata(), {pos_integer(), pos_integer()}}
  defp place(text, acc, {cursor_line, cursor_column}, base_column) do
    {line, column} = start_of(text)
    literal = Map.get(text, :literal) || ""

    newlines = String.duplicate("\n", max(line - cursor_line, 0))
    from = if line > cursor_line, do: base_column, else: cursor_column
    padding = String.duplicate(" ", max(column - from, 0))

    {[acc, newlines, padding, literal], {line, column + String.length(literal)}}
  end

  @spec start_of(struct()) :: {pos_integer(), pos_integer()}
  defp start_of(node) do
    case Map.get(node, :sourcepos) do
      %{start: {line, column}} -> {line, column}
      _other -> {1, 1}
    end
  end
end
