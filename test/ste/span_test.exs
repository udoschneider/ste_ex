defmodule Ste.SpanTest do
  use ExUnit.Case, async: true

  alias Ste.Span

  doctest Ste.Span

  describe "rebase/2" do
    test "offsets every line by the base column, per the rectangular-block invariant" do
      base = Span.new("x", 5, 3)

      assert [first, second] =
               Span.rebase([Span.new("a", 1, 1), Span.new("b", 3, 4)], base)

      assert {first.line, first.column} == {5, 3}
      assert {second.line, second.column} == {7, 6}
    end

    test "is associative across two layers" do
      outer = Span.new("x", 10, 2)
      middle = Span.new("y", 3, 4)
      inner = Span.new("z", 2, 5)

      [once] = Span.rebase([inner], middle)
      [twice] = Span.rebase([once], outer)
      [collapsed] = Span.rebase(Span.rebase([inner], middle), outer)

      assert {twice.line, twice.column} == {collapsed.line, collapsed.column}
      assert {twice.line, twice.column} == {13, 9}
    end
  end

  describe "position/2" do
    test "counts columns in codepoints, not bytes" do
      assert Span.position("üü x", byte_size("üü ")) == {1, 4}
    end

    test "clamps an offset past the end" do
      assert Span.position("ab", 99) == {1, 3}
    end
  end
end
