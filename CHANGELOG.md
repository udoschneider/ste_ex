# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Ste.check/2` and `Ste.check_spans/2` — five mechanical prose rules over a
  text or a list of extracted spans.
- `Ste.Profile` — per-project rule configuration with `{:add, …}` / `{:remove, …}`
  word-list semantics and `read_wordlist/1` for long project vocabularies.
- `Ste.Span` and `Ste.Span.rebase/2` — position-preserving extraction, so a
  violation found inside a docstring inside a Markdown paragraph still reports
  its position in the source file.
- `Ste.Extractor` behaviour with three implementations: `Text`, `Markdown`
  and `Elixir` (docstrings, via `Code.string_to_quoted/2`).
- `Ste.Extractor.MDEx` — parser-backed Markdown extraction through the optional
  `:mdex` dependency. Handles setext headings, indented code blocks and lazy
  continuation lines, which the line scanner cannot see, and carries exact
  positions per inline run. Selected per call with `extractor:`; there is no
  automatic fallback when the dependency is absent.
- `mix ste.wordset.fetch` — vendors the MIT-licensed OpenSTE wordset into
  `priv/openste/` with a provenance manifest, validates its shape before
  writing, and detects upstream drift with `--check`. Maintainer tooling, not
  shipped in the released package.
