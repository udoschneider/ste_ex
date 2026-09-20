defmodule Ste.ProfileTest do
  use ExUnit.Case, async: true

  alias Ste.Profile

  doctest Ste.Profile

  describe "new/1" do
    test "defaults to every rule" do
      assert {:ok, profile} = Profile.new()
      assert profile.rules == Profile.all_rules()
    end

    test "rejects an unknown option rather than ignoring it" do
      assert {:error, {:unknown_options, [:setnence_cap]}} = Profile.new(setnence_cap: 20)
    end

    test "rejects an unknown rule" do
      assert {:error, {:unknown_rules, [:oxford_comma]}} = Profile.new(rules: [:oxford_comma])
    end

    test "rejects a malformed word-list spec" do
      assert {:error, {:invalid_wordlist_spec, {:append, ["x"]}}} =
               Profile.new(phrasal_verbs: {:append, ["x"]})
    end
  end

  describe "word-list specs" do
    test "add extends the default" do
      assert {:ok, profile} = Profile.new(marketing_adjectives: {:add, ["synergistic", "zesty"]})
      assert "zesty" in profile.marketing_adjectives
      assert "seamless" in profile.marketing_adjectives
    end

    test "add does not duplicate" do
      assert {:ok, profile} = Profile.new(marketing_adjectives: {:add, ["seamless"]})
      assert Enum.count(profile.marketing_adjectives, &(&1 == "seamless")) == 1
    end

    test "remove drops a default the package is wrong about for this project" do
      assert {:ok, profile} = Profile.new(phrasal_verbs: {:remove, ["wire up", "carve out"]})
      refute "wire up" in profile.phrasal_verbs
      assert "spin up" in profile.phrasal_verbs
    end

    test "replace ignores the default entirely" do
      assert {:ok, profile} = Profile.new(marketing_adjectives: {:replace, ["only"]})
      assert profile.marketing_adjectives == ["only"]
    end

    test "a bare list replaces" do
      assert {:ok, profile} = Profile.new(marketing_adjectives: ["only"])
      assert profile.marketing_adjectives == ["only"]
    end
  end

  describe "new!/1" do
    test "raises on a bad option" do
      assert_raise ArgumentError, ~r/invalid Ste.Profile options/, fn ->
        Profile.new!(sentence_cap: -1)
      end
    end
  end

  describe "read_wordlist/1" do
    @tag :tmp_dir
    test "ignores blanks and comments, and trims trailing comments", %{tmp_dir: dir} do
      path = Path.join(dir, "vocabulary.txt")
      File.write!(path, "# a comment\n\nseam\nrung  # inline comment\n\n  band  \n")

      assert {:ok, ["seam", "rung", "band"]} = Profile.read_wordlist(path)
    end

    test "reports a missing file" do
      assert {:error, :enoent} = Profile.read_wordlist("nope.txt")
    end
  end
end
