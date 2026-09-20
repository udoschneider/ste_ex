defmodule Ste.Wordset.FetchTest do
  use ExUnit.Case, async: true

  alias Ste.Wordset.Fetch

  @wordset %{
    "set_name" => "openste - v1.01",
    "description" => "Open source Simplified Technical English word list",
    "words" => [
      %{"title" => "a", "wordstatus" => "approved", "spacypos" => "DET"},
      %{"title" => "ability", "wordstatus" => "approved", "spacypos" => "NOUN"},
      %{"title" => "abandon", "wordstatus" => "unapproved", "spacypos" => "VERB"}
    ],
    "alternatives" => [
      %{"title" => "abandon", "alt_title" => "stop"},
      %{"title" => "able", "alt_title" => "can"}
    ]
  }

  defp body, do: JSON.encode!(@wordset)

  defp fetcher(overrides \\ %{}) do
    fn url ->
      cond do
        Map.has_key?(overrides, url) -> Map.fetch!(overrides, url)
        String.ends_with?(url, "openste.json") -> {:ok, Map.get(overrides, :wordset, body())}
        String.ends_with?(url, "LICENSE") -> {:ok, Map.get(overrides, :license, "MIT License\n")}
        true -> {:error, :unexpected_url}
      end
    end
  end

  defp manifest(dir), do: dir |> Path.join("manifest.json") |> File.read!() |> JSON.decode!()

  describe "run/1 writing" do
    @tag :tmp_dir
    test "writes the wordset, the licence and a manifest", %{tmp_dir: dir} do
      assert {:ok, result} = Fetch.run(dir: dir, fetcher: fetcher())

      assert result.outcome == :written
      assert result.set_name == "openste - v1.01"
      assert Enum.sort(result.files) == ["LICENSE", "manifest.json", "openste.json"]

      assert File.read!(Path.join(dir, "openste.json")) == body()
      assert File.read!(Path.join(dir, "LICENSE")) == "MIT License\n"
    end

    @tag :tmp_dir
    test "records provenance rather than just the bytes", %{tmp_dir: dir} do
      assert {:ok, _} = Fetch.run(dir: dir, fetcher: fetcher())

      recorded = manifest(dir)
      assert recorded["source"] == "https://github.com/openste/openste"
      assert recorded["license"] == "MIT"
      assert recorded["ref"] == "main"
      assert recorded["set_name"] == "openste - v1.01"
    end

    @tag :tmp_dir
    test "records counts, so an upstream reshape shows up in a diff", %{tmp_dir: dir} do
      assert {:ok, result} = Fetch.run(dir: dir, fetcher: fetcher())

      assert result.counts == %{
               "words" => 3,
               "approved" => 2,
               "unapproved" => 1,
               "alternatives" => 2
             }

      assert manifest(dir)["counts"] == result.counts
    end

    @tag :tmp_dir
    test "records a sha256 per file that matches the bytes on disk", %{tmp_dir: dir} do
      assert {:ok, _} = Fetch.run(dir: dir, fetcher: fetcher())

      for {name, entry} <- manifest(dir)["files"] do
        on_disk =
          dir
          |> Path.join(name)
          |> File.read!()
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        assert entry["sha256"] == on_disk, "checksum mismatch for #{name}"
        assert entry["url"] =~ "raw.githubusercontent.com/openste/openste/main/"
      end
    end

    @tag :tmp_dir
    test "a ref reaches the URLs, so a commit SHA can pin the fetch", %{tmp_dir: dir} do
      assert {:ok, _} = Fetch.run(dir: dir, ref: "0c1d2e3", fetcher: fetcher())

      recorded = manifest(dir)
      assert recorded["ref"] == "0c1d2e3"
      assert recorded["files"]["openste.json"]["url"] =~ "/openste/openste/0c1d2e3/"
    end

    @tag :tmp_dir
    test "creates the directory when it does not exist", %{tmp_dir: dir} do
      nested = Path.join(dir, "deep/er")
      assert {:ok, _} = Fetch.run(dir: nested, fetcher: fetcher())
      assert File.exists?(Path.join(nested, "openste.json"))
    end
  end

  describe "run/1 with check: true" do
    @tag :tmp_dir
    test "passes and writes nothing when upstream is unchanged", %{tmp_dir: dir} do
      assert {:ok, _} = Fetch.run(dir: dir, fetcher: fetcher())
      before = File.stat!(Path.join(dir, "openste.json"))

      assert {:ok, result} = Fetch.run(dir: dir, check: true, fetcher: fetcher())
      assert result.outcome == :unchanged
      assert File.stat!(Path.join(dir, "openste.json")).mtime == before.mtime
    end

    @tag :tmp_dir
    test "reports drift naming the file and both checksums", %{tmp_dir: dir} do
      assert {:ok, _} = Fetch.run(dir: dir, fetcher: fetcher())

      moved = JSON.encode!(Map.put(@wordset, "description", "changed upstream"))

      assert {:error, {:drift, [{"openste.json", was, now}]}} =
               Fetch.run(dir: dir, check: true, fetcher: fetcher(%{wordset: moved}))

      assert was != now
      assert manifest(dir)["files"]["openste.json"]["sha256"] == was
    end

    @tag :tmp_dir
    test "says what to do when there is no manifest yet", %{tmp_dir: dir} do
      assert {:error, {:no_manifest, path, :enoent}} =
               Fetch.run(dir: dir, check: true, fetcher: fetcher())

      assert path == Path.join(dir, "manifest.json")
    end
  end

  describe "run/1 validation" do
    @tag :tmp_dir
    test "rejects a body that is not JSON", %{tmp_dir: dir} do
      assert {:error, {:invalid_json, _}} =
               Fetch.run(dir: dir, fetcher: fetcher(%{wordset: "<html>404</html>"}))

      refute File.exists?(Path.join(dir, "openste.json"))
    end

    @tag :tmp_dir
    test "rejects JSON that is not an object", %{tmp_dir: dir} do
      assert {:error, {:unexpected_json, _}} =
               Fetch.run(dir: dir, fetcher: fetcher(%{wordset: "[1,2,3]"}))
    end

    @tag :tmp_dir
    test "rejects a wordset missing required keys", %{tmp_dir: dir} do
      stripped = JSON.encode!(Map.drop(@wordset, ["alternatives", "words"]))

      assert {:error, {:missing_keys, missing}} =
               Fetch.run(dir: dir, fetcher: fetcher(%{wordset: stripped}))

      assert Enum.sort(missing) == ["alternatives", "words"]
    end

    @tag :tmp_dir
    test "rejects a reshaped words key", %{tmp_dir: dir} do
      reshaped = JSON.encode!(Map.put(@wordset, "words", %{"a" => "approved"}))

      assert {:error, {:not_a_list, "words"}} =
               Fetch.run(dir: dir, fetcher: fetcher(%{wordset: reshaped}))
    end

    @tag :tmp_dir
    test "writes nothing when validation fails", %{tmp_dir: dir} do
      assert {:error, _} = Fetch.run(dir: dir, fetcher: fetcher(%{wordset: "nope"}))
      refute File.exists?(Path.join(dir, "manifest.json"))
    end
  end

  describe "run/1 transport failures" do
    @tag :tmp_dir
    test "surfaces a download failure naming the file", %{tmp_dir: dir} do
      failing = fn _url -> {:error, {:http_status, 404}} end

      assert {:error, {:download_failed, "openste.json", {:http_status, 404}}} =
               Fetch.run(dir: dir, fetcher: failing)
    end

    @tag :tmp_dir
    test "surfaces a failure on the second file too", %{tmp_dir: dir} do
      partial = fn url ->
        if String.ends_with?(url, "LICENSE"),
          do: {:error, :timeout},
          else: {:ok, body()}
      end

      assert {:error, {:download_failed, "LICENSE", :timeout}} =
               Fetch.run(dir: dir, fetcher: partial)
    end

    @tag :tmp_dir
    test "rejects a non-binary body", %{tmp_dir: dir} do
      assert {:error, {:invalid_body, "openste.json", nil}} =
               Fetch.run(dir: dir, fetcher: fn _ -> {:ok, nil} end)
    end
  end

  describe "source_url/0" do
    test "names the upstream project" do
      assert Fetch.source_url() == "https://github.com/openste/openste"
    end
  end
end
