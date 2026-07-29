# Mermaid Diagrams

Several docs in this project embed diagrams as ```` ```mermaid ```` fences. ExDoc
does not draw them: it emits the fence as `<pre><code class="mermaid">` and a
script tag loads Mermaid from a CDN, which parses the block in the reader's
browser. That means a diagram with a syntax error is not a build failure — it is
a bomb icon on the published page, discovered by whoever reads it next.

This has happened more than once, so `mix docs.mermaid` now checks the diagrams.

## The check

    $ mix docs.mermaid                 # every Markdown file git tracks
    $ mix docs.mermaid docs/adr/*.md   # just these

It extracts every Mermaid block, runs each through the real `mermaid.parse()`
inside a headless Chrome, and exits non-zero listing `file:line|block N|error`
for anything that fails. It runs as part of `mix precommit` and again in CI.

Two details are load-bearing:

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
