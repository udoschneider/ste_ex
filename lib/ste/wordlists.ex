defmodule Ste.Wordlists do
  @moduledoc """
  The default word lists behind three of the five rules.

  These are the package's opinion, not a standard. Every list is overridable per
  project through `Ste.Profile` — `{:add, …}` to extend, `{:remove, …}` to drop a
  word the package is wrong about for your domain. The `:remove` direction is not
  decoration: a project whose house style genuinely uses `wire up` should be able
  to say so without forking this package.
  """

  @marketing_adjectives ~w(
    seamless seamlessly robust powerful effortless effortlessly blazing
    comprehensive holistic synergistic unparalleled unmatched turnkey
    cutting-edge state-of-the-art best-in-class world-class industry-leading
    next-generation revolutionary game-changing frictionless delightful
  )

  @phrasal_verbs [
    "spin up",
    "dive into",
    "dive in",
    "reach out",
    "dig into",
    "drill down",
    "circle back",
    "touch base",
    "kick off",
    "roll out",
    "ramp up",
    "tee up",
    "flesh out",
    "pan out",
    "shake out",
    "wire up",
    "carve out",
    "double down",
    "zero in"
  ]

  @passive_exceptions ~w(
    complicated sophisticated dedicated detailed limited related interested
    concerned advanced mixed involved experienced qualified skilled talented
    motivated organized determined excited pleased surprised worried tired
    bored confused unexpected intended supposed located known given
  )

  @irregular_participles ~w(
    built made sent kept done held found read set put left lost meant brought
    thought caught taught sought bought told sold drawn shown dealt felt met
    paid run cut split spread hit let shut
  )

  @doc "Default marketing adjectives flagged by the `:marketing_adjective` rule."
  @spec marketing_adjectives() :: [String.t()]
  def marketing_adjectives, do: @marketing_adjectives

  @doc "Default soft phrasal verbs flagged by the `:phrasal_verb` rule."
  @spec phrasal_verbs() :: [String.t()]
  def phrasal_verbs, do: @phrasal_verbs

  @doc """
  Participles that read as adjectives, so a preceding be-verb is not passive voice.

  Without these, `the schema is complicated` counts as passive.
  """
  @spec passive_exceptions() :: [String.t()]
  def passive_exceptions, do: @passive_exceptions

  @doc """
  Irregular past participles the `-ed` / `-en` pattern misses.

  `the report was sent` is passive, but `sent` matches neither suffix.
  """
  @spec irregular_participles() :: [String.t()]
  def irregular_participles, do: @irregular_participles
end
