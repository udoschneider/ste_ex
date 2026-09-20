defmodule Ste.Extractor.MDExTest do
  use ExUnit.Case, async: true

  alias Ste.Extractor
  alias Ste.Extractor.MDEx, as: Parser

  doctest Ste.Extractor.MDEx

  defp spans(source, opts \\ []) do
    {:ok, spans} = Parser.spans(source, opts)
    spans
  end

  defp texts(source), do: source |> spans() |> Enum.map(&String.trim(&1.text))

  defp rules(source) do
    {:ok, violations} = Ste.check_markdown(source, Ste.Profile.new!(), extractor: Parser)
    violations
  end

  defp scanner_rules(source) do
    {:ok, violations} = Ste.check_markdown(source, Ste.Profile.new!())
    violations
  end

  defp at(source, %{line: line, column: column}, length) do
    source |> String.split("\n") |> Enum.at(line - 1) |> String.slice(column - 1, length)
  end

  describe "block exclusions" do
    test "drops frontmatter, headings, code, tables, blockquotes and images" do
      source = """
      ---
      title: Robust
      ---

      # Robust heading

      | robust | cell |
      | ------ | ---- |

      > robust quote

      ![robust alt](x.png)

      ```
      robust code
      ```

      real prose
      """

      assert texts(source) == ["real prose"]
    end

    test "keeps list item prose" do
      assert texts("- prose one\n- prose two\n") == ["prose one", "prose two"]
    end
  end

  describe "what the scanner cannot see" do
    test "a setext heading is a heading, not a paragraph" do
      source = "Robust heading\n==============\n\nplain prose\n"

      assert texts(source) == ["plain prose"]
      assert rules(source) == []

      # The scanner looks for a leading '#', so it scores the underlined title.
      assert [%{rule: :marketing_adjective, line: 1}] = scanner_rules(source)
    end

    test "an indented code block is code" do
      source = "Intro line.\n\n    robust code here\n\nOutro line.\n"

      assert texts(source) == ["Intro line.", "Outro line."]
      assert rules(source) == []

      # The scanner has no state for four-space indentation.
      assert [%{rule: :marketing_adjective, line: 3}] = scanner_rules(source)
    end

    test "an autolink is a destination, not prose" do
      source = "See https://robust.example.com/seamless now.\n"

      assert rules(source) == []
    end

    test "a link keeps its label and drops its destination" do
      source = "See [the robust label](https://seamless.example.com) now.\n"

      assert [violation] = rules(source)
      assert violation.rule == :marketing_adjective
      assert at(source, violation, 6) == "robust"
    end
  end

  describe "positions" do
    test "prose after an inline code span lands on the right character" do
      source = "Trailing `inline` robust prose.\n"

      assert [violation] = rules(source)
      assert {violation.line, violation.column} == {1, 19}
      assert at(source, violation, 6) == "robust"
    end

    test "a list item's continuation line keeps its indentation" do
      source = "- item one that wraps\n  onto a robust line\n"

      assert [violation] = rules(source)
      assert violation.line == 2
      assert at(source, violation, 6) == "robust"
    end

    test "a span is anchored at the paragraph's leftmost column" do
      [span] = spans("- item one\n  continuing here\n")
      assert {span.line, span.column} == {1, 3}
    end
  end

  describe "soft-break grouping" do
    test "a sentence that wraps is one sentence, not two" do
      wrapped =
        "word word word word word word word word word word word\nword word word word word word word word word word word.\n"

      assert [%{rule: :long_sentence, detail: %{words: 22}}] = rules(wrapped)
    end

    test "the rebuilt paragraph keeps each run on its own line" do
      [span] = spans("first line here\nsecond line here\n")
      assert span.text == "first line here\nsecond line here"
    end
  end

  describe "options" do
    test "default_extension/0 enables tables and autolinks" do
      extension = Parser.default_extension()
      assert extension[:table] == true
      assert extension[:autolink] == true
    end

    test "a caller can turn an extension off" do
      source = "| robust | cell |\n| ------ | ---- |\n"

      assert texts(source) == []
      assert ["| robust | cell |" <> _] = texts_with(source, extension: [table: false])
    end
  end

  # The {:error, {:missing_dependency, :mdex}} branch is unreachable from this
  # suite: :mdex is an optional dependency, so it is present in this project's
  # own test environment. It was verified against a consumer that path-depends
  # on this package without :mdex, where the library compiles warning-free and
  # Ste.Extractor.MDEx.spans/2, Ste.check_markdown/3 with extractor: and
  # Ste.check_elixir/3 with markdown: all return that error rather than falling
  # back to the scanner.

  describe "behaviour conformance" do
    test "implements Ste.Extractor" do
      assert Extractor in Parser.module_info(:attributes)[:behaviour]
    end
  end

  defp texts_with(source, opts), do: source |> spans(opts) |> Enum.map(&String.trim(&1.text))
end
