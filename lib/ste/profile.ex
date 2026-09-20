defmodule Ste.Profile do
  @moduledoc """
  Per-project rule configuration, built once and passed to every check.

  ## Why a struct rather than application config

  A linter's rule set is *input*, not application configuration. One project
  routinely needs two rule sets live at the same time — a strict one for
  reference documentation and a loose one for working notes, with different
  sentence caps and different rules enabled. Application config cannot express
  that, and a library that reads `Application.get_env/2` for its core behaviour
  breaks the moment two consumers share a VM.

  ## Word-list specs

  Every word list takes one of four shapes:

    * `nil` (or omitted) — the package default
    * `{:add, words}` — the default plus `words`
    * `{:remove, words}` — the default minus `words`
    * `{:replace, words}` or a plain list — exactly `words`

  ## Examples

      iex> {:ok, profile} = Ste.Profile.new(sentence_cap: 30, rules: [:semicolon])
      iex> profile.sentence_cap
      30

      iex> {:ok, profile} = Ste.Profile.new(phrasal_verbs: {:remove, ["wire up"]})
      iex> "wire up" in profile.phrasal_verbs
      false

      iex> Ste.Profile.new(sentence_cap: 0)
      {:error, {:invalid_option, :sentence_cap, 0}}
  """

  alias Ste.Violation
  alias Ste.Wordlists

  @all_rules [
    :long_sentence,
    :passive_voice,
    :phrasal_verb,
    :marketing_adjective,
    :semicolon
  ]

  @wordlists [
    marketing_adjectives: &Wordlists.marketing_adjectives/0,
    phrasal_verbs: &Wordlists.phrasal_verbs/0,
    passive_exceptions: &Wordlists.passive_exceptions/0,
    irregular_participles: &Wordlists.irregular_participles/0
  ]

  @type list_spec ::
          [String.t()]
          | {:add | :remove | :replace, [String.t()]}
          | nil

  @type t :: %__MODULE__{
          rules: [Violation.rule()],
          sentence_cap: pos_integer(),
          marketing_adjectives: [String.t()],
          phrasal_verbs: [String.t()],
          passive_exceptions: [String.t()],
          irregular_participles: [String.t()]
        }

  defstruct rules: @all_rules,
            sentence_cap: 20,
            marketing_adjectives: [],
            phrasal_verbs: [],
            passive_exceptions: [],
            irregular_participles: []

  @doc "Every rule this package knows how to score."
  @spec all_rules() :: [Violation.rule()]
  def all_rules, do: @all_rules

  @doc """
  Builds a profile, returning `{:error, reason}` rather than raising on a bad option.

  See the module documentation for the accepted word-list specs.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) do
    with :ok <- validate_keys(opts),
         {:ok, rules} <- validate_rules(Keyword.get(opts, :rules, @all_rules)),
         {:ok, cap} <- validate_cap(Keyword.get(opts, :sentence_cap, 20)),
         {:ok, lists} <- resolve_wordlists(opts) do
      {:ok, struct!(%__MODULE__{rules: rules, sentence_cap: cap}, lists)}
    end
  end

  @doc "Builds a profile or raises `ArgumentError`. For call sites where a bad option is a bug."
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    case new(opts) do
      {:ok, profile} -> profile
      {:error, reason} -> raise ArgumentError, "invalid Ste.Profile options: #{inspect(reason)}"
    end
  end

  @doc """
  Whether `rule` is enabled in `profile`.

  ## Examples

      iex> profile = Ste.Profile.new!(rules: [:semicolon])
      iex> {Ste.Profile.enabled?(profile, :semicolon), Ste.Profile.enabled?(profile, :long_sentence)}
      {true, false}
  """
  @spec enabled?(t(), Violation.rule()) :: boolean()
  def enabled?(%__MODULE__{rules: rules}, rule), do: rule in rules

  @doc """
  Reads a newline-delimited word list from disk.

  Blank lines and `#` comments are ignored. Project vocabularies get long — a
  file you append one line to is reachable in a way a keyword list buried in a
  build config is not, and a rule whose exemption path has friction gets
  switched off instead of corrected.
  """
  @spec read_wordlist(Path.t()) :: {:ok, [String.t()]} | {:error, File.posix()}
  def read_wordlist(path) do
    with {:ok, contents} <- File.read(path) do
      words =
        contents
        |> String.split("\n")
        |> Enum.map(&(&1 |> String.split("#", parts: 2) |> hd() |> String.trim()))
        |> Enum.reject(&(&1 == ""))

      {:ok, words}
    end
  end

  @doc "Reads a word list or raises `File.Error`."
  @spec read_wordlist!(Path.t()) :: [String.t()]
  def read_wordlist!(path) do
    case read_wordlist(path) do
      {:ok, words} -> words
      {:error, reason} -> raise File.Error, reason: reason, action: "read word list", path: path
    end
  end

  @spec validate_keys(keyword()) :: :ok | {:error, term()}
  defp validate_keys(opts) do
    known = [:rules, :sentence_cap | Keyword.keys(@wordlists)]

    case Keyword.keys(opts) -- known do
      [] -> :ok
      unknown -> {:error, {:unknown_options, unknown}}
    end
  end

  @spec validate_rules(term()) :: {:ok, [Violation.rule()]} | {:error, term()}
  defp validate_rules(rules) when is_list(rules) do
    case rules -- @all_rules do
      [] -> {:ok, rules}
      unknown -> {:error, {:unknown_rules, unknown}}
    end
  end

  defp validate_rules(other), do: {:error, {:invalid_option, :rules, other}}

  @spec validate_cap(term()) :: {:ok, pos_integer()} | {:error, term()}
  defp validate_cap(cap) when is_integer(cap) and cap > 0, do: {:ok, cap}
  defp validate_cap(other), do: {:error, {:invalid_option, :sentence_cap, other}}

  @spec resolve_wordlists(keyword()) :: {:ok, keyword()} | {:error, term()}
  defp resolve_wordlists(opts) do
    Enum.reduce_while(@wordlists, {:ok, []}, fn {key, default_fun}, {:ok, acc} ->
      case resolve(default_fun.(), Keyword.get(opts, key)) do
        {:ok, list} -> {:cont, {:ok, [{key, list} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec resolve([String.t()], list_spec()) :: {:ok, [String.t()]} | {:error, term()}
  defp resolve(default, nil), do: {:ok, default}
  defp resolve(_default, {:replace, words}) when is_list(words), do: {:ok, Enum.uniq(words)}
  defp resolve(default, {:add, words}) when is_list(words), do: {:ok, Enum.uniq(default ++ words)}
  defp resolve(default, {:remove, words}) when is_list(words), do: {:ok, default -- words}
  defp resolve(_default, words) when is_list(words), do: {:ok, Enum.uniq(words)}
  defp resolve(_default, other), do: {:error, {:invalid_wordlist_spec, other}}
end
