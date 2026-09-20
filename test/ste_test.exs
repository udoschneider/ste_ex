defmodule SteTest do
  use ExUnit.Case, async: true

  doctest Ste

  describe "check/2" do
    test "finds each rule" do
      rules =
        "The change was applied; it is a seamless way to spin up a very long sentence that keeps going and going and going past the cap."
        |> Ste.check()
        |> Enum.map(& &1.rule)
        |> Enum.sort()

      assert :long_sentence in rules
      assert :passive_voice in rules
      assert :phrasal_verb in rules
      assert :marketing_adjective in rules
      assert :semicolon in rules
    end

    test "honours a profile that disables rules" do
      profile = Ste.Profile.new!(rules: [:semicolon])
      assert [%{rule: :semicolon}] = Ste.check("It is robust; truly.", profile)
    end

    test "honours a removed word" do
      profile = Ste.Profile.new!(phrasal_verbs: {:remove, ["wire up"]})
      assert [] = Ste.check("We wire up the gate.", profile)
      assert [%{rule: :phrasal_verb}] = Ste.check("We wire up the gate.")
    end
  end

  describe "check_spans/2" do
    test "rebases violations onto their span" do
      span = Ste.Span.new("it is robust", 42, 7)
      assert [violation] = Ste.check_spans([span])
      assert violation.rule == :marketing_adjective
      assert {violation.line, violation.column} == {42, 13}
    end
  end

  describe "check_file/2" do
    @tag :tmp_dir
    test "dispatches on extension", %{tmp_dir: dir} do
      md = Path.join(dir, "doc.md")
      File.write!(md, "# Robust\n\nThis is robust.\n")
      assert {:ok, [%{rule: :marketing_adjective, line: 3}]} = Ste.check_file(md)

      txt = Path.join(dir, "notes.txt")
      File.write!(txt, "# Robust\n")
      assert {:ok, [%{rule: :marketing_adjective, line: 1}]} = Ste.check_file(txt)
    end

    test "reports a missing file" do
      assert {:error, :enoent} = Ste.check_file("does/not/exist.md")
    end
  end

  describe "extractor selection" do
    @tag :tmp_dir
    test "check_file/3 passes the extractor through to a markdown file", %{tmp_dir: dir} do
      path = Path.join(dir, "doc.md")
      File.write!(path, "Robust heading\n==============\n\nplain prose\n")

      assert {:ok, [%{rule: :marketing_adjective, line: 1}]} = Ste.check_file(path)
      assert {:ok, []} = Ste.check_file(path, Ste.Profile.new!(), extractor: Ste.Extractor.MDEx)
    end

    test "check_markdown/3 defaults to the zero-dependency scanner" do
      assert {:ok, [%{line: 1}]} = Ste.check_markdown("Robust heading\n==============\n")
    end
  end

  describe "positions through every layer" do
    setup do
      source =
        Enum.join(
          [
            "defmodule Demo do",
            "  @moduledoc \"\"\"",
            "  Some intro.",
            "",
            "  - a list item that is robust",
            "",
            "  ```",
            "  robust code is ignored",
            "  ```",
            "  \"\"\"",
            "end",
            ""
          ],
          "\n"
        )

      %{source: source, lines: String.split(source, "\n")}
    end

    test "a violation inside Markdown inside a heredoc lands on the right character",
         %{source: source, lines: lines} do
      assert {:ok, [violation]} = Ste.check_elixir(source)
      assert violation.rule == :marketing_adjective
      assert {violation.line, violation.column} == {5, 25}

      line = Enum.at(lines, violation.line - 1)
      assert String.slice(line, violation.column - 1, 6) == "robust"
    end

    test "fenced code inside a docstring is not scored", %{source: source} do
      assert {:ok, violations} = Ste.check_elixir(source)
      refute Enum.any?(violations, &(&1.line == 8))
    end

    test "markdown: false scores the raw docstring, fences included", %{source: source} do
      assert {:ok, violations} = Ste.check_elixir(source, Ste.Profile.new!(), markdown: false)
      assert Enum.any?(violations, &(&1.line == 8))
    end
  end
end
