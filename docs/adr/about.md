# About

**Decisions** are documents that capture the details of important choices that were made during the development of this software, along with the context and consequences to be remembered.

These decision documents are an excellent opportunity to write down what was in your head during the development of a code change, the design of a feature, or the choice of one vendor/library over another. Having these details written down greatly benefits future code contributors, including your future self, as they question why something was done a certain way in the past.

## When to write one

Write a decision only when **all three** of these are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons.

If a choice is easy to reverse, skip it; you'll just reverse it. If it isn't surprising, nobody will wonder why. If there was no real alternative, there is nothing to record beyond "we did the obvious thing." A choice that fails this test but still needs writing down is usually a coding standard (see `CODING_STANDARDS.md` at the repo root) or a glossary term (see [`CONTEXT.md`](../../CONTEXT.md)), not a decision.

## Keep them short

A decision can be a single paragraph, and most should be. One to three sentences — the situation, the choice, the reason — is a complete record. `__template.md` offers **Problem Statement**, **Decision Made**, and **Consequences & Tradeoffs** as optional sections; use one only when it carries weight the summary cannot, and delete the rest. Filling out every heading turns a record into an essay that nobody rereads.

## Amending an earlier decision

Decision documents are **immutable**. Never rewrite one to match how the code works today — that turns the record of *why we chose* into a second, competing statement of *what we do*, and the two drift.

When a new decision narrows, extends, or overturns an older one, say so in the new document **and add a pointer to the top of the old one**, directly under its title:

```md
# In-Window Secondary Views

> **Scoped by [ADR 0022](0022-report-refreshes-on-demand.md)** — the Report is a
> read-only view and refreshes on demand rather than on every `{:book_updated}`.
```

The pointer is the one edit an existing decision may receive. It costs a line, keeps the original text honest about its own moment, and — most importantly — means a reader who lands on the old document learns immediately that it is not the end of the story, instead of having to reconstruct the chain from the newest document backwards.

## Naming

Decision files are named with a four-digit sequential prefix that increments by one in creation order, followed by a short kebab-case slug (e.g. `0001-which-automerge-rust-library.md`). To add a decision, take the next number after the highest existing one.

For more on the practice of writing decisions (also known as architecture decision records in other circles) see [this GitHub repo][adr].

[adr]: https://github.com/joelparkerhenderson/architecture-decision-record
