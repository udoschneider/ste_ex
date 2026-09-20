defmodule Ste.Extractor.ElixirTest do
  use ExUnit.Case, async: true

  alias Ste.Extractor.Elixir, as: ElixirExtractor

  doctest Ste.Extractor.Elixir
  doctest Ste.Extractor.Text

  defp source(lines), do: Enum.join(lines ++ [""], "\n")

  defp spans(lines, opts \\ [markdown: false]) do
    {:ok, spans} = ElixirExtractor.spans(source(lines), opts)
    spans
  end

  describe "heredoc positions" do
    test "content starts one line below the delimiter, at the indentation column" do
      [span] =
        spans([
          "defmodule Demo do",
          "  @moduledoc \"\"\"",
          "  first line",
          "  \"\"\"",
          "end"
        ])

      assert {span.line, span.column} == {3, 3}
      assert span.text == "first line\n"
    end

    test "a deeper indentation moves the column, not the line" do
      [span] =
        spans([
          "defmodule Demo do",
          "  defmodule Inner do",
          "    @moduledoc \"\"\"",
          "    text",
          "    \"\"\"",
          "  end",
          "end"
        ])

      assert {span.line, span.column} == {4, 5}
    end
  end

  describe "which attributes are extracted" do
    test "moduledoc, doc and typedoc" do
      spans =
        spans([
          "defmodule Demo do",
          "  @moduledoc \"module prose\"",
          "  @typedoc \"type prose\"",
          "  @type t :: term()",
          "  @doc \"function prose\"",
          "  def f, do: :ok",
          "end"
        ])

      assert Enum.map(spans, & &1.text) == ["module prose", "type prose", "function prose"]
    end

    test "@doc false carries no prose and is skipped" do
      assert spans([
               "defmodule Demo do",
               "  @doc false",
               "  def f, do: :ok",
               "end"
             ]) == []
    end

    test "an interpolated docstring is skipped rather than mispositioned" do
      assert spans([
               "defmodule Demo do",
               "  @version \"1.0\"",
               ~S(  @moduledoc "version #{@version}"),
               "end"
             ]) == []
    end
  end

  describe "single-line docstrings" do
    test "are placed just inside the opening quote" do
      lines = ["defmodule Demo do", "  @doc \"prose here\"", "  def f, do: :ok", "end"]
      [span] = spans(lines)

      assert span.line == 2

      assert lines
             |> Enum.at(span.line - 1)
             |> String.slice(span.column - 1, 5) == "prose"
    end
  end

  describe "composition with Markdown" do
    test "a docstring is Markdown by default, so doctests are not scored" do
      lines = [
        "defmodule Demo do",
        "  @moduledoc \"\"\"",
        "  Real prose.",
        "",
        "  ## Examples",
        "",
        "      iex> robust()",
        "  \"\"\"",
        "end"
      ]

      texts = lines |> spans(markdown: true) |> Enum.map(&String.trim(&1.text))
      assert texts == ["Real prose.", "iex> robust()"]

      raw = lines |> spans(markdown: false) |> Enum.map(& &1.text)
      assert [<<"Real prose.", _::binary>>] = raw
    end
  end

  describe "pluggable markdown extractor" do
    test "a module name selects the extractor" do
      lines = [
        "defmodule Demo do",
        "  @moduledoc \"\"\"",
        "  Robust heading",
        "  ==============",
        "",
        "  plain prose",
        "  \"\"\"",
        "end"
      ]

      # The setext heading is prose to the scanner and a heading to the parser.
      assert ["Robust heading\n==============", "plain prose"] =
               lines |> spans(markdown: true) |> Enum.map(&String.trim(&1.text))

      assert ["plain prose"] =
               lines |> spans(markdown: Ste.Extractor.MDEx) |> Enum.map(&String.trim(&1.text))
    end

    test "positions survive the parser-backed composition" do
      source =
        source([
          "defmodule Demo do",
          "  @moduledoc \"\"\"",
          "  Some intro.",
          "",
          "  - a list item that is robust",
          "  \"\"\"",
          "end"
        ])

      assert {:ok, [violation]} =
               Ste.check_elixir(source, Ste.Profile.new!(), markdown: Ste.Extractor.MDEx)

      assert violation.rule == :marketing_adjective

      assert source
             |> String.split("\n")
             |> Enum.at(violation.line - 1)
             |> String.slice(violation.column - 1, 6) == "robust"
    end

    test "an extractor failure propagates rather than being swallowed" do
      defmodule FailingExtractor do
        @behaviour Ste.Extractor
        @impl Ste.Extractor
        def spans(_source, _opts \\ []), do: {:error, :boom}
      end

      lines = ["defmodule Demo do", "  @moduledoc \"prose\"", "end"]

      assert {:error, :boom} =
               ElixirExtractor.spans(source(lines), markdown: FailingExtractor)
    end
  end

  describe "errors" do
    test "a parse error is returned, not raised" do
      assert {:error, _reason} = ElixirExtractor.spans("defmodule Demo do", [])
    end
  end
end
