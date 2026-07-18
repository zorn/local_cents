# Should `@doc` restate a return shape the `@spec` already documents?

> Research note behind a documentation-style choice for LocalCents' public
> functions (e.g. the `LocalCents.Tracking` API, whose functions return
> `{:ok, document, expense}` / `{:error, changeset}`): when a `@spec` already
> states the exact return shape, should the `@doc` prose (a) restate that tuple
> literally, (b) summarize it in plain language, or (c) omit it? Sources are
> primary: the official Elixir "Writing Documentation" and "Typespecs" guides,
> the **installed** source of Ecto, Phoenix, Plug, and Req under `deps/`, and
> Elixir Forum threads. No secondary blog write-ups were used as authorities.

## Question

Our public functions carry precise specs, for example:

```elixir
@spec add_expense(Book.t(), String.t(), Decimal.t()) ::
        {:ok, Automerge.doc(), Expense.t()} | {:error, Ecto.Changeset.t()}
```

The `@spec` already pins the return shape exactly. Reading a `@doc` that then
says "Returns `{:ok, doc, expense}` on success or `{:error, changeset}` on
failure" feels like noise — it re-encodes, in prose, something the reader can see
one line down and that ExDoc already renders from the spec. So: when the `@spec`
fully captures the return shape, should the `@doc` restate it, summarize it, or
leave it out?

## What Elixir itself says

Two official guides split the labor cleanly between the two attributes.

**The Typespecs guide says the spec _is_ the documentation of the signature.**
From [Typespecs](https://hexdocs.pm/elixir/typespecs.html), specs are useful
because "they provide documentation (for example, tools such as ExDoc show type
specifications in the documentation)" and are consumed by Dialyzer. The spec is
where the argument and return *types* live, and ExDoc renders it inline next to
the doc — so a caller reading the docs already sees the shape.

**The Writing Documentation guide steers `@doc` toward meaning, not mechanics.**
From [Writing Documentation](https://hexdocs.pm/elixir/writing-documentation.html):

- Keep "the first paragraph of the documentation concise and simple, typically
  one-line" — a behavioral summary, not a type transcript.
- Demonstrate behavior with runnable examples under an `## Examples` heading
  (doctests), which is where the *concrete* shape naturally appears — as real
  return values the reader can see and the test suite verifies.
- Documentation "is an explicit contract between you and users of your API"; it
  is aimed at the caller who wants to know what a function *does* and *means*.

Neither guide asks prose to restate the spec. Taken together they assign the
return **shape** to the `@spec` (and to doctest output), and reserve the `@doc`
prose for what the shape *means* — the conditions under which each branch is
returned. This is the same principle our house docs already encode for
moduledocs ("explain the _why_, not the _what_… a reader can already see the
function names and typespecs", `docs/moduledoc-style.md`) and for comments
("never restate the signature", `docs/comment-style.md`).

## What the popular libraries do

The prevailing pattern across the best-documented libraries is consistent:
**the summary line describes the behavior semantically, the `@spec` carries the
literal tuple, and the doctest `## Examples` show the shape by example. Prose
names the _conditions_, not the tuple.**

**Ecto — `Ecto.Changeset.apply_action/2`** (`deps/ecto/lib/ecto/changeset.ex:2312`):

```elixir
@doc """
Applies the changeset action only if the changes are valid.

If the changes are valid, all changes are applied to the changeset data.
If the changes are invalid, no changes are applied, and an error tuple
is returned with the changeset containing the action that was attempted
to be applied.
...
## Examples

    iex> {:ok, data} = apply_action(changeset, :update)
    iex> {:error, changeset} = apply_action(changeset, :update)
    %Ecto.Changeset{action: :update}
"""
@spec apply_action(t, action) :: {:ok, Ecto.Schema.t() | data} | {:error, t}
```

The prose explains *when* you get success vs. an error tuple and *what the error
carries* (a changeset with the action set) — meaning the spec can't express. The
literal `{:ok, …} | {:error, t}` lives in the `@spec`, and the shape shows up
concretely in the doctest. The prose never writes out the tuple as such.

**Phoenix — `Phoenix.Token.verify/4`** (`deps/phoenix/lib/phoenix/token.ex:165`):

```elixir
@doc """
Decodes the original data from the token and verifies its integrity.
...
      iex> Phoenix.Token.verify(secret, namespace, token, max_age: 86400)
      {:ok, 99}
...
      iex> Phoenix.Token.verify(secret, namespace, expired, max_age: 86400)
      {:error, :expired}
"""
@spec verify(context, binary, binary, [shared_opt | max_age_opt]) ::
        {:ok, term} | {:error, :expired | :invalid | :missing}
```

The one-line summary is purely behavioral. The rich `{:error, :expired |
:invalid | :missing}` shape is in the `@spec`; the prose instead explains the
*causes* of each error (expired, invalid, or `nil` token) and demonstrates them
in doctests — again, meaning over mechanics.

**Req — `Req.get/2`** (`deps/req/lib/req.ex:584`):

```elixir
@doc """
Makes a GET request and returns a response or an error.
...
"""
@spec get(url() | keyword() | Req.Request.t(), options :: keyword()) ::
        {:ok, Req.Response.t()} | {:error, Exception.t()}
```

This is the middle ground done well: the summary *summarizes* the return in
plain language ("a response or an error") without writing the tuple. The literal
`{:ok, Req.Response.t()} | {:error, Exception.t()}` is left entirely to the
`@spec`. Its bang sibling `get!/2` differs only in prose — "returns a response or
raises an error" (`deps/req/lib/req.ex:626`).

**Plug — `Plug.Conn` mutators** (`deps/plug/lib/plug/conn.ex:299`, `:352`, `:393`):
functions like `assign/3`, `put_private/3`, and `put_status/3` have a `@spec …
:: t` and a `@doc` that describes what the function does to the conn; none spend
a sentence announcing "returns the conn" — the `:: t` says it.

The one place prose *does* touch the shape is small, self-explanatory
accessors, and even there it binds the shape to a condition rather than mirroring
the spec — e.g. `Ecto.Changeset.fetch_change/2`
(`deps/ecto/lib/ecto/changeset.ex:1836`): "returns `{:ok, value}` if the change
is present or `:error` if it's not." Note the value of that sentence is the
*if-present / if-not* mapping, not the tuple itself. It reads as meaning, and it
still lets the `@spec` (`{:ok, term} | :error`) own the types.

## What the community says

The forum discussion is less about "may I omit the return shape from prose" and
more about a broader, settled ecosystem instinct: **don't hand-repeat type
information that already lives in a `@spec`.** The same DRY reflex appears in
threads debating whether to add a `@spec` at all when an `@impl`/`@callback`
already defines the contract (["Should using `@impl true` cause docs to show the
callback spec?"](https://elixirforum.com/t/should-using-impl-true-cause-docs-to-show-the-callback-spec/47034)),
and in the guidance to extract `@type`s rather than repeat a shape across many
specs ([Typespecs](https://hexdocs.pm/elixir/typespecs.html) — "Defining function
specs by repeating types over and over can become annoying"). The community
treats the `@spec`/ExDoc rendering as the canonical home of the shape; prose
restating it is redundant by the same logic.

More telling than any single thread is the *demonstrated* norm above: across
Ecto, Phoenix, Plug, and Req — the libraries this project depends on and models
its style after — restating the return tuple in prose is simply not done. The
convention is settled in practice, not debated.

## Synthesis and recommendation

When a `@spec` fully captures the return shape, the `@doc` should **not restate
the tuple literally**. Choose between summarizing and omitting by what the shape
*means*:

1. **Omit the shape from prose when the spec is self-explanatory.** If the summary
   sentence plus the `@spec` (which ExDoc renders inline) and an `## Examples`
   doctest already make the return obvious, don't add a "Returns `{:ok, …}` /
   `{:error, …}`" sentence. This is the Phoenix/Plug default.

2. **Summarize in plain language when it aids the reader** — the Req pattern:
   "returns a response or an error", "returns the updated book". Name the outcome
   semantically; do not transcribe the tuple.

3. **Always explain the _conditions and meaning_ of each branch when they aren't
   obvious** — the Ecto pattern: *when* is it `:ok` vs `:error`, and *what does
   the error value carry* (a changeset with the action set; `:expired` vs
   `:invalid`). This is the part the `@spec` genuinely can't express, and it is
   the highest-value thing `@doc` prose can add about the return.

4. **Let doctests carry the concrete shape.** A `## Examples` block that shows
   `{:ok, data} = …` and `{:error, changeset} = …` documents the shape by
   demonstration, stays honest (it's tested), and reads better than a prose
   restatement.

In short: **`@spec` owns the shape; doctests show it; `@doc` prose explains what
it means and when each branch happens.** For our `{:ok, doc, expense}` /
`{:error, changeset}` functions, that means a one-line behavioral summary, no
literal tuple in the prose, a sentence on when you get an error and that it
carries a changeset, and a doctest that shows both branches.

Suggested encoding for the house standards: add a bullet to the function-doc
guidance (alongside the existing `@spec` rules in `CODING_STANDARDS.md`, or in a
function-doc section of the moduledoc/comment style docs) — *"When a `@spec`
fully states the return shape, don't restate the tuple in `@doc` prose. Give a
behavioral summary, explain the conditions and meaning of each return branch, and
let the `@spec` and an `## Examples` doctest carry the literal shape."* This is a
direct extension of the existing "explain the _why_, not the _what_" and "never
restate the signature" rules to the return value.
