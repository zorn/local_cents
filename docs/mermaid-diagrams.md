# Mermaid Diagrams

Several docs in this project embed diagrams as ```` ```mermaid ```` fences. ExDoc
does not draw them: it emits the fence as `<pre><code class="mermaid">` and a
script tag loads Mermaid from a CDN, which parses the block in the reader's
browser. That means a diagram with a syntax error is not a build failure — it is
a bomb icon on the published page, discovered by whoever reads it next.

This has happened more than once, so `mix docs.mermaid` now checks the diagrams.

## The check

    $ mix docs.mermaid                 # every tracked `.md` and `lib/*.ex`
    $ mix docs.mermaid docs/adr/*.md   # just these

It extracts every Mermaid block, runs each through the real `mermaid.parse()`
inside a headless Chrome, and exits non-zero listing `file:line|block N|error`
for anything that fails. It runs as part of `mix precommit` and again in CI.

The scope is not only the guides. ExDoc injects its Mermaid script into *every*
page it generates, so a fence inside a `@moduledoc` renders in the reader's
browser exactly like one here — `lib/*.ex` is checked for that reason. Test files
are not, so a fixture is free to hold a deliberately broken diagram.

Two more details are load-bearing:

- **It parses at the pinned version, not the latest.** `LocalCents.Docs.Mermaid`
  owns that pin, and `mix.exs` builds the docs' `<script>` tag from the same
  function, so the version you are checked against is always the version your
  readers load. Syntax the [Mermaid live editor](https://mermaid.live) accepts
  can still fail here — the live editor tracks latest.

- **`mix precommit` skips rather than fails when it cannot run.** The check needs
  Chrome and (on a cold cache) a network connection to fetch Mermaid. Rather than
  block a contributor who has neither, `precommit` lets the check skip with a
  notice; CI runs it with `--strict`, where a check that cannot run is a failure.
  If you have a browser somewhere unusual, point `CHROME_BIN` at it.

## Why this is homegrown

A check we maintain ourselves is the kind of thing worth justifying, so: as of
July 2026 Mermaid ships `mermaid.parse()` as an API and nothing else — no
official linter, no official Action. Every tool in this space is a wrapper around
the same call this check makes, so the choice was never "official versus
homegrown," only whose wrapper.

The field surveyed:

- [`@mermaid-js/mermaid-cli`](https://github.com/mermaid-js/mermaid-cli) is the
  only mature option, but it renders rather than validates — you infer the
  verdict from an exit code after producing an SVG you throw away — and its
  Markdown mode never opens `lib/*.ex`. It also arrives via npm and Puppeteer, or
  a Docker image.
- [`maid`](https://github.com/probelabs/maid) reimplements the grammar in
  Chevrotain. That answers "is this plausibly Mermaid," not "does *our pinned
  version* accept it" — and both gotchas below are exactly that second question.
- The rest ([`md-mermaid-lint`](https://github.com/suwa-sh/md-mermaid-lint),
  [`mermaid-validate`](https://github.com/Zabaca/mermaid-validate) and friends)
  do call the real parser, but are single-maintainer projects in the single
  digits of stars, and none document pinning the Mermaid version.

That last point is what settled it. The pin coupling described above is the whole
value of the check, and adopting any of these turns one fact into two that have
to be hand-synced — a Docker tag or npm version on one side, `@version` on the
other. Drift there reintroduces precisely the bugs this exists to catch.

The cost we accept in exchange is a dependency on Chrome's `--dump-dom` and
`--virtual-time-budget` flags. If those ever change behaviour the harness reports
no results, which `--strict` turns into a red build rather than a silent pass.

## Gotchas worth knowing

Both of these produced a broken diagram in this repo, and neither produces a
warning anywhere in the toolchain.

### A second `:` ends a state transition label

In a `stateDiagram-v2`, the `:` after a transition opens the label and the *next*
`:` closes it — so a label containing a colon is truncated and the remainder is
parsed as a new description:

```text
A --> B : persist, stop :normal      %% fails to parse
A --> B : persist, stop &#58;normal  %% parses, and still displays as a colon
```

`&#58;` is the escape to reach for.

### A `;` ends a statement inside note text

In a `sequenceDiagram`, `;` is a statement separator, including inside a `Note`.
The text after it is parsed as a fresh statement — usually as an actor name that
is then waiting for an arrow that never comes:

```text
Note over V,S: window is open; server stays resident   %% fails to parse
Note over V,S: window is open — server stays resident  %% parses
```

Rewrite with a dash or split the note in two.
