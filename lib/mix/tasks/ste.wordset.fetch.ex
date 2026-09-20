defmodule Mix.Tasks.Ste.Wordset.Fetch do
  @shortdoc "Downloads the OpenSTE wordset into priv/"

  @moduledoc """
  Downloads the OpenSTE wordset into `priv/openste/` and writes a manifest.

      mix ste.wordset.fetch
      mix ste.wordset.fetch --check
      mix ste.wordset.fetch --ref 0c1d2e3 --dir priv/openste

  The fetched files are **vendored**: committed to this repository and shipped
  inside the released package. Nothing is downloaded while a consumer builds.

  ## Options

    * `--dir` — where to write. Defaults to `priv/openste`.
    * `--ref` — upstream git ref. Defaults to `main`. Upstream publishes no
      tags, so a commit SHA is the only exact pin.
    * `--check` — download and compare against the committed manifest without
      writing. Exits non-zero when upstream has moved, which is what makes this
      usable as a drift gate.

  ## Provenance

  Source: <https://github.com/openste/openste>, MIT, © openSTE.org. OpenSTE is
  an independent re-derivation; no ASD publication, rule text or dictionary data
  is involved.
  """

  use Mix.Task

  alias Ste.Wordset.Fetch

  @doc false
  @impl Mix.Task
  def run(argv) do
    {opts, _rest} =
      OptionParser.parse!(argv, strict: [dir: :string, ref: :string, check: :boolean])

    case Fetch.run(opts) do
      {:ok, result} -> report(result)
      {:error, reason} -> Mix.raise(explain(reason))
    end
  end

  @spec report(Fetch.t()) :: :ok
  defp report(%{outcome: :unchanged} = result) do
    Mix.shell().info("#{result.set_name} is current — #{summary(result)}")
  end

  defp report(%{outcome: :written} = result) do
    Mix.shell().info("Wrote #{result.set_name} to #{result.dir}/ — #{summary(result)}")
    Mix.shell().info("Files: #{Enum.join(result.files, ", ")}")
    Mix.shell().info("Commit these; they ship inside the package.")
  end

  @spec summary(Fetch.t()) :: String.t()
  defp summary(%{counts: counts}) do
    "#{counts["words"]} words (#{counts["approved"]} approved, " <>
      "#{counts["unapproved"]} unapproved), #{counts["alternatives"]} alternatives"
  end

  @spec explain(term()) :: String.t()
  defp explain({:drift, drifted}) do
    lines = Enum.map_join(drifted, "\n", fn {name, was, now} -> "  #{name}: #{was} -> #{now}" end)

    "Upstream has moved since the manifest was written:\n#{lines}\n" <>
      "Run `mix ste.wordset.fetch` to take the new version deliberately."
  end

  defp explain({:no_manifest, path, _reason}) do
    "No manifest at #{path}. Run `mix ste.wordset.fetch` first."
  end

  defp explain({:download_failed, name, reason}) do
    "Could not download #{name}: #{inspect(reason)}"
  end

  defp explain({:missing_keys, missing}) do
    "The wordset is missing #{Enum.join(missing, ", ")}. Upstream changed shape; " <>
      "check the source before taking it."
  end

  defp explain({:not_a_list, key}) do
    "The wordset's #{inspect(key)} is not a list. Upstream changed shape; " <>
      "check the source before taking it."
  end

  defp explain(reason), do: "Fetching the wordset failed: #{inspect(reason)}"
end
