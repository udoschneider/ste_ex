defmodule Ste.Wordset.Fetch do
  @moduledoc """
  Downloads the OpenSTE wordset into `priv/` and records where it came from.

  ## Why a task rather than a build-time download

  The fetched file is **vendored** — downloaded once by a maintainer, committed,
  and shipped inside the released package. It is not fetched while a consumer
  builds.

  A build-time download would make every consumer's build non-hermetic, invisible
  to their SBOM, and dependent on a host staying up. And it would buy nothing:
  OpenSTE is MIT licensed and published so that tools can ship it. The only thing
  a download-at-build-time would move is *when* the copy happens, not whether one
  is made.

  What this task adds over a manual download is a reproducible refresh path and a
  manifest that makes upstream drift detectable — see `run/1`'s `:check` option.

  ## Provenance

  Source: <https://github.com/openste/openste>, MIT, © openSTE.org. No ASD
  publication, rule text or dictionary data is involved; OpenSTE is an
  independent re-derivation published under its own licence.
  """

  @source_url "https://github.com/openste/openste"
  @raw_base "https://raw.githubusercontent.com/openste/openste"

  @files [
    {"vocabulary/openste.json", "openste.json"},
    {"LICENSE", "LICENSE"}
  ]

  @required_keys ~w(set_name description words alternatives)
  @wordset_file "openste.json"
  @manifest_file "manifest.json"

  @type download :: %{name: String.t(), url: String.t(), body: binary(), sha256: String.t()}

  @type t :: %{
          dir: Path.t(),
          ref: String.t(),
          set_name: String.t(),
          counts: %{String.t() => non_neg_integer()},
          files: [String.t()],
          outcome: :written | :unchanged
        }

  @doc """
  Fetches the wordset, validates it, and writes it with a manifest.

  ## Options

    * `:dir` — where to write. Defaults to `"priv/openste"`.
    * `:ref` — upstream git ref. Defaults to `"main"`. Upstream publishes no
      tags, so a commit SHA is the only way to pin exactly.
    * `:check` — when `true`, download and compare against the recorded
      manifest without writing. Returns `{:error, {:drift, details}}` if the
      upstream content no longer matches. Defaults to `false`.
    * `:fetcher` — a one-argument function from URL to `{:ok, binary}` or
      `{:error, term}`. Defaults to an `:httpc` client with peer verification.
      Tests pass a stub so the suite never touches the network.
  """
  @spec run(keyword()) :: {:ok, t()} | {:error, term()}
  def run(opts \\ []) do
    dir = Keyword.get(opts, :dir, "priv/openste")
    ref = Keyword.get(opts, :ref, "main")
    fetcher = Keyword.get(opts, :fetcher, &fetch_url/1)

    with {:ok, downloads} <- download_all(ref, fetcher),
         {:ok, metadata} <- validate(downloads) do
      manifest = manifest(ref, downloads, metadata)

      case Keyword.get(opts, :check, false) do
        true -> check(dir, downloads, metadata, manifest)
        false -> write(dir, downloads, metadata, manifest)
      end
    end
  end

  @doc "The upstream project this wordset comes from."
  @spec source_url() :: String.t()
  def source_url, do: @source_url

  @spec download_all(String.t(), (String.t() -> {:ok, binary()} | {:error, term()})) ::
          {:ok, [download()]} | {:error, term()}
  defp download_all(ref, fetcher) do
    Enum.reduce_while(@files, {:ok, []}, fn {remote, name}, {:ok, acc} ->
      url = Enum.join([@raw_base, ref, remote], "/")

      case fetcher.(url) do
        {:ok, body} when is_binary(body) ->
          {:cont, {:ok, acc ++ [%{name: name, url: url, body: body, sha256: sha256(body)}]}}

        {:ok, other} ->
          {:halt, {:error, {:invalid_body, name, other}}}

        {:error, reason} ->
          {:halt, {:error, {:download_failed, name, reason}}}
      end
    end)
  end

  # A silently reshaped upstream is the failure this guards: the download would
  # succeed, the file would be committed, and only the rule built on it would
  # break, far from the cause.
  @spec validate([download()]) :: {:ok, map()} | {:error, term()}
  defp validate(downloads) do
    with %{body: body} <- Enum.find(downloads, &(&1.name == @wordset_file)) || {:error, :missing},
         {:ok, json} <- decode(body),
         :ok <- require_keys(json),
         :ok <- require_list(json, "words"),
         :ok <- require_list(json, "alternatives") do
      {:ok, %{set_name: json["set_name"], counts: counts(json)}}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, {:missing_file, @wordset_file}}
    end
  end

  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  defp decode(body) do
    case JSON.decode(body) do
      {:ok, json} when is_map(json) -> {:ok, json}
      {:ok, other} -> {:error, {:unexpected_json, other}}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  @spec require_keys(map()) :: :ok | {:error, term()}
  defp require_keys(json) do
    case Enum.reject(@required_keys, &Map.has_key?(json, &1)) do
      [] -> :ok
      missing -> {:error, {:missing_keys, missing}}
    end
  end

  @spec require_list(map(), String.t()) :: :ok | {:error, term()}
  defp require_list(json, key) do
    if is_list(json[key]), do: :ok, else: {:error, {:not_a_list, key}}
  end

  @spec counts(map()) :: %{String.t() => non_neg_integer()}
  defp counts(json) do
    words = json["words"]

    %{
      "words" => length(words),
      "approved" => Enum.count(words, &(&1["wordstatus"] == "approved")),
      "unapproved" => Enum.count(words, &(&1["wordstatus"] == "unapproved")),
      "alternatives" => length(json["alternatives"])
    }
  end

  @spec manifest(String.t(), [download()], map()) :: map()
  defp manifest(ref, downloads, metadata) do
    %{
      "source" => @source_url,
      "license" => "MIT",
      "ref" => ref,
      "set_name" => metadata.set_name,
      "counts" => metadata.counts,
      "files" => Map.new(downloads, fn d -> {d.name, %{"url" => d.url, "sha256" => d.sha256}} end)
    }
  end

  @spec write(Path.t(), [download()], map(), map()) :: {:ok, t()} | {:error, term()}
  defp write(dir, downloads, metadata, manifest) do
    with :ok <- File.mkdir_p(dir),
         :ok <- write_files(dir, downloads),
         :ok <- File.write(Path.join(dir, @manifest_file), encode(manifest)) do
      {:ok, result(dir, manifest, metadata, downloads, :written)}
    end
  end

  @spec write_files(Path.t(), [download()]) :: :ok | {:error, term()}
  defp write_files(dir, downloads) do
    Enum.reduce_while(downloads, :ok, fn d, :ok ->
      case File.write(Path.join(dir, d.name), d.body) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:write_failed, d.name, reason}}}
      end
    end)
  end

  @spec check(Path.t(), [download()], map(), map()) :: {:ok, t()} | {:error, term()}
  defp check(dir, downloads, metadata, manifest) do
    path = Path.join(dir, @manifest_file)

    with {:ok, raw} <- read_manifest(path),
         {:ok, stored} <- decode(raw),
         :ok <- compare(stored, manifest) do
      {:ok, result(dir, manifest, metadata, downloads, :unchanged)}
    end
  end

  @spec read_manifest(Path.t()) :: {:ok, binary()} | {:error, term()}
  defp read_manifest(path) do
    case File.read(path) do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, {:no_manifest, path, reason}}
    end
  end

  @spec compare(map(), map()) :: :ok | {:error, term()}
  defp compare(stored, fresh) do
    drifted =
      for {name, %{"sha256" => fresh_sha}} <- fresh["files"],
          get_in(stored, ["files", name, "sha256"]) != fresh_sha,
          do: {name, get_in(stored, ["files", name, "sha256"]), fresh_sha}

    if drifted == [], do: :ok, else: {:error, {:drift, drifted}}
  end

  @spec result(Path.t(), map(), map(), [download()], :written | :unchanged) :: t()
  defp result(dir, _manifest, metadata, downloads, outcome) do
    %{
      dir: dir,
      ref: Map.get(metadata, :ref, "main"),
      set_name: metadata.set_name,
      counts: metadata.counts,
      files: Enum.map(downloads, & &1.name) ++ [@manifest_file],
      outcome: outcome
    }
  end

  @spec encode(map()) :: iodata()
  defp encode(manifest), do: [JSON.encode!(manifest), "\n"]

  @spec sha256(binary()) :: String.t()
  defp sha256(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  @spec fetch_url(String.t()) :: {:ok, binary()} | {:error, term()}
  defp fetch_url(url) do
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      request(url)
    end
  end

  @spec request(String.t()) :: {:ok, binary()} | {:error, term()}
  defp request(url) do
    # :httpc does not verify peers unless told to, and a silently unverified TLS
    # connection is the wrong default for anything that lands in a package.
    # OTP's own helper supplies the CA store and the hostname match function, so
    # this needs no reference to :public_key -- which would otherwise have to be
    # declared in extra_applications and started in every consumer's release.
    http_opts = [
      ssl: :httpc.ssl_verify_host_options(true),
      timeout: 30_000,
      connect_timeout: 10_000
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, http_opts, body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, body}
      {:ok, {{_version, status, _reason}, _headers, _body}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, {:http_error, reason}}
    end
  end
end
