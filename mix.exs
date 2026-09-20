defmodule Ste.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/udoschneider/ste_ex"

  def project do
    [
      app: :ste,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      name: "Ste",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger] ++ fetch_applications(Mix.env())]
  end

  # :inets, :ssl and :public_key are needed only by `mix ste.wordset.fetch`, a
  # maintainer tool that is not shipped in the package (see :exclude_patterns).
  # Declaring them unconditionally would add three OTP applications to every
  # consumer's release for a task they can never run.
  defp fetch_applications(env) when env in [:dev, :test], do: [:inets, :ssl, :public_key]
  defp fetch_applications(_env), do: []

  defp deps do
    [
      {:mdex, "~> 0.13", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # :mix is not a dependency, but the maintainer task implements Mix.Task and
  # calls Mix.raise/1 and Mix.shell/0. Without it in the PLT, dialyzer reports
  # the behaviour and both calls as unknown.
  defp dialyzer do
    [plt_add_apps: [:mix]]
  end

  defp description do
    "A prose linter for technical documentation. Scores mechanical writing habits " <>
      "against a re-derived subset of controlled-language rules, with position-preserving " <>
      "extractors for plain text, Markdown and Elixir docstrings."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md),
      exclude_patterns: ["lib/mix/", "lib/ste/wordset/"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", LICENSE: [title: "License"]],
      source_ref: "v#{@version}",
      groups_for_modules: [
        Extractors: [
          Ste.Extractor,
          Ste.Extractor.Text,
          Ste.Extractor.Markdown,
          Ste.Extractor.Elixir
        ]
      ]
    ]
  end
end
