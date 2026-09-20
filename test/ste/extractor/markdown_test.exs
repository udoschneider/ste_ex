defmodule Ste.Extractor.MarkdownTest do
  use ExUnit.Case, async: true

  alias Ste.Extractor.Markdown

  doctest Ste.Extractor.Markdown

  defp spans(source) do
    {:ok, spans} = Markdown.spans(source)
    spans
  end

  defp texts(source), do: source |> spans() |> Enum.map(&String.trim(&1.text))

  describe "block masking" do
    test "drops YAML frontmatter" do
      source = "---\ntitle: Robust\n---\n\nreal prose\n"
      assert texts(source) == ["real prose"]
    end

    test "only treats a leading --- as frontmatter" do
      source = "prose\n\n---\ntitle: Robust\n---\n"
      refute texts(source) == ["prose"]
    end

    test "drops fenced code, both markers" do
      assert texts("```\nrobust\n```\n\nprose\n") == ["prose"]
      assert texts("~~~\nrobust\n~~~\n\nprose\n") == ["prose"]
    end

    test "an inner fence marker does not close an outer one" do
      assert texts("~~~\n```\nrobust\n```\n~~~\n\nprose\n") == ["prose"]
    end

    test "drops headings, tables, blockquotes and thematic breaks" do
      source = """
      # Robust heading

      | robust | cell |
      | ------ | ---- |

      > robust quote

      ---

      prose
      """

      assert texts(source) == ["prose"]
    end

    test "keeps list item text but masks the marker" do
      assert texts("- prose one\n- prose two\n") == ["prose one\n  prose two"]
      assert texts("1. prose\n") == ["prose"]
    end
  end

  describe "inline masking preserves columns" do
    test "inline code" do
      [span] = spans("a `robust` b prose")
      assert span.text == "a          b prose"
    end

    test "a link keeps its label on the same column" do
      source = "see [the docs](https://example.com/x) now"
      [span] = spans(source)

      assert String.length(span.text) == String.length(source)
      assert String.slice(span.text, 5, 8) == "the docs"
      assert String.slice(source, 5, 8) == "the docs"
    end

    test "masking never changes a line's character length" do
      for source <- [
            "a `code` b",
            "see [label](https://example.com/x) now",
            "an ![alt text](image.png) here",
            "visit https://example.com/path now",
            "an <https://example.com> autolink",
            "a <span class=\"x\">tag</span> here"
          ] do
        [span] = spans(source)
        assert String.length(span.text) == String.length(source), "changed length: #{source}"
      end
    end

    test "an image is masked entirely" do
      [span] = spans("a ![robust alt](x.png) b")
      assert span.text == "a                      b"
    end

    test "bare URLs and autolinks are masked" do
      assert [%{text: "see        " <> _}] = spans("see https://example.com/robust")
      assert [%{text: "see " <> rest}] = spans("see <https://example.com>")
      assert String.trim(rest) == ""
    end

    test "HTML tags are masked" do
      [span] = spans("a <br/> b")
      assert span.text == "a       b"
    end
  end

  describe "grouping" do
    test "paragraphs are separated by blank lines and carry their first line number" do
      source = "one\ntwo\n\nthree\n"
      assert [first, second] = spans(source)
      assert {first.line, String.trim(first.text)} == {1, "one\ntwo"}
      assert {second.line, String.trim(second.text)} == {4, "three"}
    end

    test "a fully masked line separates paragraphs" do
      source = "one\n# heading\ntwo\n"
      assert [first, second] = spans(source)
      assert {first.line, second.line} == {1, 3}
    end

    test "every span starts at column 1, keeping the block rectangular" do
      assert Enum.all?(spans("- a\n\n> b\n\nc\n"), &(&1.column == 1))
    end
  end
end
