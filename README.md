# Ste

A prose linter for technical documentation. Text in, violations out.

Five mechanical writing rules, scored over prose that an extractor has located in
a source document. Every violation carries a line and column in the original
file — even when the prose was three layers down, inside a Markdown list item,
inside a heredoc, inside an `.ex` file.

```elixir
Ste.check("The report was sent; it is seamless.")
#=> [%Ste.Violation{rule: :passive_voice,        line: 1, column: 12, text: "was sent"},
#    %Ste.Violation{rule: :semicolon,            line: 1, column: 20, text: ";"},
#    %Ste.Violation{rule: :marketing_adjective,  line: 1, column: 28, text: "seamless"}]
```

## Contents

- [What this is not](#what-this-is-not)
- [Installation](#installation)
- [Quick start](#quick-start)
- [The five rules](#the-five-rules)
- [Profiles](#profiles)
- [Extractors](#extractors)
- [Positions](#positions)
- [What lives elsewhere](#what-lives-elsewhere)
- [Vendored data](#vendored-data)
- [Limitations](#limitations)
- [Roadmap](#roadmap)
- [Development](#development)

## What this is not

`Ste` is **not** an implementation of ASD-STE100 or of any other published
standard, and no conformance is claimed or implied. Its rules are re-derived
from widely known controlled-language advice and cover a small subset of it.

This project is **not affiliated with, endorsed by, or certified by** ASD or the
STEMG. No text, rule wording or dictionary data from any ASD publication is
included in this repository or in the released package.

The detectors are heuristics with a deliberate false-positive rate. The
passive-voice rule has no grammar model and over-counts by design; sentence
segmentation guards abbreviations and decimals but is still regex, not a parser.
A single measurement means little. The direction between two measurements is
what carries information.

## Installation

```elixir
def deps do
  [{:ste, "~> 0.1"}]
end
```

Requires Elixir 1.18 or later, for the standard library's `JSON` module.

No required runtime dependencies, and no OTP application beyond `:logger`. Add
`{:mdex, "~> 0.13"}` to opt into parser-backed Markdown extraction — see
[Extractors](#extractors).

## Quick start

```elixir
Ste.check("plain prose")                        # → [%Ste.Violation{}, …]
{:ok, violations} = Ste.check_markdown(md)      # scores paragraphs, skips code
{:ok, violations} = Ste.check_elixir(source)    # scores @doc / @moduledoc
{:ok, violations} = Ste.check_file("doc.md")    # extractor chosen by extension
Ste.check_spans(spans, profile)                 # bring your own extractor
```

`check/2` returns a bare list because it cannot fail: it takes prose and applies
rules. The others take an extractor, so they can fail, and their return type says
so.

Choose the extractor per call:

```elixir
Ste.check_markdown(md,        profile, extractor: Ste.Extractor.MDEx)
Ste.check_file("doc.md",      profile, extractor: Ste.Extractor.MDEx)
Ste.check_elixir(source,      profile, markdown:  Ste.Extractor.MDEx)
```

### A violation

```elixir
%Ste.Violation{
  rule: :long_sentence,
  line: 42,
  column: 3,
  text: "The sentence that broke the cap …",
  detail: %{words: 27, cap: 20}
}
```

`line` and `column` are 1-based and address the original file. `detail` carries
whatever the rule knows: the word count and the cap it broke, or the participle
that triggered a passive hit.

## The five rules

| Rule | Counts | Configurable through |
| --- | --- | --- |
| `:long_sentence` | one per sentence over the profile's word cap | `:sentence_cap` |
| `:passive_voice` | be-verb + past participle | `:passive_exceptions`, `:irregular_participles` |
| `:phrasal_verb` | soft phrasal verbs | `:phrasal_verbs` |
| `:marketing_adjective` | a short fixed list | `:marketing_adjectives` |
| `:semicolon` | every semicolon in prose | — |

**`:long_sentence`** splits on `.`, `!` and `?`, then merges back across known
abbreviations and decimals, so `see e.g. the table` and `version 1.4 shipped` do
not read as two short sentences hiding a long one.

**`:passive_voice`** matches a be-verb, an optional adverb, and a participle —
`-ed`, `-en`, or one of the irregulars (`sent`, `built`, `kept`) that neither
suffix catches. `:passive_exceptions` holds participles that read as adjectives,
so `the schema is complicated` does not fire.

**`:phrasal_verb`** targets the soft ones only — `spin up`, `dive into`,
`reach out`, `wire up`, `carve out` — matching across arbitrary whitespace, so a
phrasal verb broken over a line still counts. It does not touch the phrasal verbs
that have no one-word equivalent.

**`:marketing_adjective`** is a short fixed list (`seamless`, `robust`,
`frictionless`, `turnkey`, …), matched case-insensitively and on word
boundaries, so `seamlessness` does not fire.

**`:semicolon`** has no exceptions. A semicolon in technical prose is nearly
always two sentences that have not been separated yet.

Every list is overridable — see below. Inspect the defaults with
`Ste.Wordlists.marketing_adjectives/0`, `phrasal_verbs/0`,
`passive_exceptions/0` and `irregular_participles/0`.

## Profiles

A rule set is *input*, not application configuration. One project routinely needs
a strict profile for reference documentation and a loose one for working notes,
live at the same time, with different caps and different rules enabled.
Application config cannot express that, and a library that reads
`Application.get_env/2` for its core behaviour breaks the moment two consumers
share a VM. So there is no `config :ste`; you build a profile and pass it.

```elixir
strict =
  Ste.Profile.new!(
    sentence_cap: 20,
    rules: [:long_sentence, :passive_voice, :semicolon, :marketing_adjective],
    marketing_adjectives: {:add, ~w(synergistic holistic)},
    phrasal_verbs: {:remove, ["wire up", "carve out"]}
  )

loose = Ste.Profile.new!(sentence_cap: 30, rules: [:long_sentence])

Ste.check(reference_doc, strict)
Ste.check(working_note, loose)
```

### Word-list specs

Every list takes one of four shapes:

| Spec | Result |
| --- | --- |
| omitted | the package default |
| `{:add, words}` | default plus `words`, deduplicated |
| `{:remove, words}` | default minus `words` |
| `{:replace, words}` or a bare list | exactly `words` |

The `:remove` direction is not decoration. A project whose house style genuinely
uses `wire up` should say so rather than fork this package, and the same goes for
a domain where `robust` is a technical term with a meaning.

### Word lists in files

Project vocabularies get long, and a rule whose exemption path has friction gets
switched off instead of corrected. So lists can live on disk, one word per line,
with `#` comments and blank lines ignored:

```elixir
Ste.Profile.new!(
  marketing_adjectives: {:add, Ste.Profile.read_wordlist!(".ste/marketing.txt")}
)
```

`read_wordlist/1` returns `{:ok, words}` or `{:error, posix}` for callers that
would rather not raise.

### Building a profile safely

`Ste.Profile.new/1` returns `{:ok, profile}` or `{:error, reason}` and rejects
rather than ignores: an unknown option, an unknown rule, a non-positive cap and a
malformed word-list spec each come back as a tagged error. `new!/1` raises
`ArgumentError` instead, for call sites where a bad option is a bug.

`Ste.Profile.all_rules/0` lists every rule; `enabled?/2` asks whether one is on.

## Extractors

An extractor answers one question — *which parts of this file are prose, and
where are they?* — and answers it without concatenating, so positions survive.

| Module | Input | Dependency |
| --- | --- | --- |
| `Ste.Extractor.Text` | anything | none |
| `Ste.Extractor.Markdown` | Markdown, line scanner | none |
| `Ste.Extractor.MDEx` | Markdown, CommonMark parser | `:mdex` (optional) |
| `Ste.Extractor.Elixir` | `.ex` / `.exs` docstrings | none |

All four implement the `Ste.Extractor` behaviour:

```elixir
@callback spans(source :: String.t(), opts :: keyword()) ::
            {:ok, [Ste.Span.t()]} | {:error, term()}
```

Implement it yourself for a markup this package does not handle, and feed the
result to `Ste.check_spans/2`.

### Masking, not deleting

Extractors replace non-prose with spaces of the same character count. A fenced
code block becomes blank lines of the same length; an inline code run becomes the
same number of spaces. Deleting would shift every column after the cut and make
the reported position wrong in exactly the files that need it most. Masking costs
nothing and keeps each extracted block rectangular, which is what makes
composition correct.

### Two Markdown extractors, and how to choose

`Ste.Extractor.Markdown` scans lines. It costs nothing and handles fences,
frontmatter, ATX headings, tables, blockquotes, list markers, inline code, links,
images, bare URLs and HTML tags.

`Ste.Extractor.MDEx` parses CommonMark through
[mdex](https://hex.pm/packages/mdex). It is more correct, and the cost is a Rust
NIF plus five transitive dependencies, with a precompiled binary downloaded at
build time.

What the parser gets right that the scanner cannot, each pinned by a test that
asserts the scanner gets it *wrong*:

| Case | Scanner | Parser |
| --- | --- | --- |
| Setext heading (`Title` over `======`) | scored as prose | heading |
| Indented code block (four spaces) | scored as prose | code |
| Lazy continuation lines | approximated | exact |
| Link destination | masked by regex | a structural attribute, never text |
| Inline run positions | preserved by padding | carried per node |

There is no automatic fallback. A missing `:mdex` returns
`{:error, {:missing_dependency, :mdex}}` rather than quietly scanning instead,
because the same input must not score differently depending on what happens to be
installed.

The parser rebuilds each paragraph into one span rather than emitting one per
node. CommonMark splits a wrapped paragraph on soft breaks, and scoring those
separately would cut every sentence that wraps — with sentence length being one
of the five rules. Each run is padded to its true column and excluded inline
content leaves a gap, so the rebuilt block is rectangular and every character
still sits where the source puts it.

`Ste.Extractor.MDEx.default_extension/0` shows which CommonMark extensions are
on. Tables and autolinks are enabled because without them a pipe row and a bare
URL both arrive as ordinary prose. Override per call with `extension:`.

### Docstrings are Markdown

A docstring is Markdown, and most well-documented modules are mostly doctests.
Scoring one as raw text means scoring `iex>` blocks and `## Examples` headings as
prose. So `Ste.Extractor.Elixir` runs a Markdown extractor over each docstring:

```elixir
Ste.Extractor.Elixir.spans(source)                              # scanner
Ste.Extractor.Elixir.spans(source, markdown: Ste.Extractor.MDEx) # parser
Ste.Extractor.Elixir.spans(source, markdown: false)             # raw text
```

It reads `@moduledoc`, `@doc` and `@typedoc` through
`Code.string_to_quoted/2` — no dependency. The literal metadata carries
everything needed to place a docstring exactly:

```elixir
[delimiter: "\"\"\"", indentation: 2, line: 2, column: 14]
```

Elixir dedents a heredoc when it builds the string, so content begins one line
below the opening delimiter at `indentation + 1`.

## Positions

`Ste.Span` is a run of text plus where it starts in the source it came from.
`Ste.Span.rebase/2` re-expresses spans found *inside* a span in the outer
coordinate system, and `Ste.Violation.rebase/2` does the same for violations.
That is what lets extractors compose.

```elixir
base  = Ste.Span.new("…", 10, 3)
inner = [Ste.Span.new("a", 1, 1), Ste.Span.new("b", 2, 1)]

Ste.Span.rebase(inner, base)
#=> [%Ste.Span{text: "a", line: 10, column: 3},
#    %Ste.Span{text: "b", line: 11, column: 3}]
```

### The rectangular-block invariant

`rebase/2` assumes the base span's text is a *rectangular block*: every one of
its lines begins at `base.column` in the enclosing source. That holds for a
dedented heredoc and for a Markdown block, which is why both extractors compose.

It does not hold for text starting mid-line, such as `@doc "some prose"`, where
the first line begins at column 8 and a second would begin at column 1. So
`Ste.Extractor.Elixir` emits exact spans only for heredocs and degrades to
attribute-line granularity otherwise, rather than reporting a confidently wrong
column.

### Worked example

Given this source, `Ste.check_elixir/3` reports the `robust` on **line 5, column
25** — through a heredoc, through Markdown, through a list item — and does not
report the `robust` inside the fenced block:

```elixir
defmodule Demo do
  @moduledoc """
  Some intro.

  - a list item that is robust

  ```
  robust code is ignored
  ```
  """
end
```

## What lives elsewhere

This package stops at violations. Aggregation — per-file rates, a corpus score, a
committed floor that fails a build on regression — is the caller's. Every project
wants a different shape, and none of it needs to be in a library.

## Vendored data

`priv/openste/` holds the [OpenSTE](https://www.openste.org/) wordset: 1,951
words (909 approved, 1,042 unapproved) and 1,589 alternative mappings, MIT
licensed, © openSTE.org. It is committed to this repository and ships inside the
released package. Nothing is downloaded while you build.

OpenSTE is an independent re-derivation of the one-approved-word-per-concept
idea, published under its own licence precisely so that tools can ship it. No ASD
publication is involved.

Maintainers refresh it with a mix task, which validates the shape before writing,
records a SHA-256 per file and writes `priv/openste/manifest.json`:

```sh
mix ste.wordset.fetch           # download, validate, write
mix ste.wordset.fetch --check   # fail if upstream has moved
mix ste.wordset.fetch --ref SHA # pin to a commit
```

`--check` is the drift gate: it re-downloads, compares checksums against the
committed manifest, and exits non-zero when upstream has changed. Taking a new
version is then a deliberate act with a reviewable diff, and the manifest's
recorded counts make a silent upstream reshape visible in that diff.

The task is **not** shipped in the package. A consumer has no reason to refetch,
and keeping it out is what lets this library declare no OTP application beyond
`:logger`.

No rule reads the wordset yet — see [Roadmap](#roadmap).

## Limitations

Stated plainly, because a linter that hides its failure modes gets trusted more
than it should be.

- **The passive detector over-counts.** No grammar model, a carve-out list
  instead.
- **Sentence segmentation is regex.** It guards abbreviations and decimals; it
  will still be wrong somewhere.
- **The line scanner misses setext headings, indented code blocks and lazy
  continuation lines.** `Ste.Extractor.MDEx` does not.
- **Single-line `@doc "…"` columns are exact only without escape sequences.**
  `\n` is two characters in the source and one in the parsed value. Heredocs are
  always exact; for the rest, the line is the guarantee and the column is best
  effort.
- **Interpolated docstrings are skipped.** `@moduledoc "v#{@version}"` is not a
  string literal, so there is no single run of text to place.
- **The rules encode one house style.** They are a starting point to override,
  not a standard to conform to.

## Roadmap

- XML, HTML and HEEx extractors, in that order.
- A vocabulary rule over the vendored wordset. Its `alternatives` list maps each
  unapproved word to its approved replacements (`abandon` → `stop`, `able` →
  `can` / `possible`), so both readings are buildable: flagging unapproved words
  outright, or the lower-noise **synonym rotation** — inverting the mapping into
  concept groups and firing only when one document uses two members of the same
  group.

## Development

```sh
mix deps.get
mix test                          # 117 tests, no network access
mix format --check-formatted
mix credo --strict
mix dialyzer
mix docs
```

The suite never touches the network. `Ste.Wordset.Fetch.run/1` takes an
injectable `:fetcher`, and the tests pass a stub.

One branch is unreachable from the suite: `{:error, {:missing_dependency, :mdex}}`
cannot fire while `:mdex` is present in this project's own test environment. It
is verified against a consumer that path-depends on this package without `:mdex`.

## License

MIT. See [LICENSE](LICENSE).

The vendored OpenSTE wordset in `priv/openste/` is separately MIT licensed,
© openSTE.org; its licence travels with it in `priv/openste/LICENSE`.
