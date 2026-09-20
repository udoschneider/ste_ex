defmodule Mix.Tasks.Ste.Wordset.FetchTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Ste.Wordset.Fetch

  # The task is a thin shell over Ste.Wordset.Fetch: it parses options, reports,
  # and translates errors. The behaviour lives in Ste.Wordset.FetchTest, which
  # injects a fetcher so the suite never touches the network. The task itself
  # exposes no fetcher option, so only its argument handling is reachable here.

  test "rejects an unknown switch rather than ignoring it" do
    assert_raise OptionParser.ParseError, ~r/--nope/, fn ->
      Fetch.run(["--nope"])
    end
  end

  test "rejects a switch given without its value" do
    assert_raise OptionParser.ParseError, fn ->
      Fetch.run(["--ref"])
    end
  end
end
