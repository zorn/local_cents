# Software Terms

Modeling vocabulary we use when building LocalCents. These are general
software / domain-driven-design concepts rather than domain nouns — for the
project's domain glossary see [CONTEXT.md](../CONTEXT.md).

The name of the application is `LocalCents`, no space. When represented inside Elixir this is atomized as `:local_cents`.

## Structs, Values, and Entities 

* **Struct** -- When we need to represent a complex domain concept that Elixir
  primitives can not represent, we often lean on [Elixir Structs] and [Ecto
  Schemas] to build those concepts.
* **Entity** -- Many domain concepts are not defined primarily by their
  attributes but rather by their lifespan identity; these are called entities.
  Entities typically change over time, and equality is based on identity, not
  attributes.
* **Value Object** -- When you only care about the attributes of a domain
  concept, classify it as a value object. These value objects describe things
  but have no identity in and of themselves. Generally, value objects do not
  change over time.

> **Aside:** Working in the Elixir environment, we tend to say `Value` over
> `Value Object` since that distinction is needed only for object-oriented
> languages. 

[Elixir Structs]: https://hexdocs.pm/elixir/main/structs.html
[Ecto Schemas]: https://hexdocs.pm/ecto/Ecto.html#module-schema

### An example: Is an `Address` an entity or a value object? It depends.

Whether or not any domain concept should consider an entity or a value object
depends entirely on its usage. An example from [Domain-Driven Design]:

> In software for a mail-order company, an address is needed to confirm the
> credit card, and to address the parcel. But if a roommate also orders from the
> same company, it is not important to realize they are in the same location.
> Address is a VALUE OBJECT. 
> 
> In software for the postal service, intended to organize delivery routes, the
> country could be formed into a hierarchy of regions, cities, postal zones, and
> blocks, terminating in individual addresses. These address objects would
> derive their zip code from their parent in the hierarchy, and if the postal
> service decided to reassign postal zones, all the addresses within would go
> along for the ride. Here, Address is an ENTITY.
>
> In software for an electric utility company, an address corresponds to a
> destination for the company's lines and service. If roommates each called to
> order electrical service, the company would need to realize it. Address is an
> ENTITY. Alternatively, the model could associate utility service with a
> "dwelling," an ENTITY with an attribute of address. Then Address would be a
> VALUE OBJECT.
>
> Tracking the identity of ENTITIES is essential, but attaching identity to
> other objects can hurt system performance, add analytical work, and muddle the
> model by making all objects look the same. 

[Domain-Driven Design]: https://www.goodreads.com/book/show/179133.Domain_Driven_Design

## Raw vs. plain data

* **Raw** -- a domain value in its stored, _untyped_ form: the shape it takes
  inside the Automerge document before the domain parses it. In the tracking
  context an expense's `date` and `cost` are *raw* strings (`"2026-07-11"`,
  `"12.34"`) that `LocalCents.Tracking.BookDocument` parses into typed values
  (`Date`, `Decimal`); `LocalCents.Tracking.ExAutomerge`'s `state` / `raw_expense`
  are the raw maps (atom keys, string values). Use **raw** whenever you mean this
  stored, un-parsed form.
* **Plain data** -- plain, immutable Elixir values (structs, maps, lists) as
  opposed to process state — the "plain data in, plain data out" property of the
  functional core (see [ADR 0014](adr/0014-functional-core-process-shell.md)).
  This is about *where* the data lives (not a process), not whether it is typed, so
  it is a different axis from **raw**.

## Stamping a change

* **Stamp** (verb) -- to record the unix-seconds `time` on an Automerge change so a
  Book's **Last Updated** advances. A command that mutates a Book *stamps* the change
  with a `DateTime` (the injected `:now`), which the shell converts to whole unix
  seconds and hands the NIF; `document_updated_at/1` reads the most recent such stamp
  back out (see [ADR 0012](adr/0012-book-last-updated-timestamp.md)). Prefer this verb
  over "timestamp" when you mean the act of recording that value on a write. By
  contrast, a read-only path — a **Report**, `list_expenses/1` — *stamps no change*:
  it writes nothing, so it never advances `updated_at`.

  Unrelated: the `bond-stamp` CSS class in the web layer is the rubber-stamp *press*
  interaction on a button (it shifts toward its shadow on hover) and has nothing to do
  with change times.

## Client

* **Client** -- which of the two places a page is being rendered into: the native
  desktop window (`:desktop`) or an ordinary browser tab (`:browser`). Both are served
  by the same Phoenix routes; they differ in what the surrounding shell can do for a
  view, so several affordances change shape between them — **Open** is a native window
  on the desktop and a link in a browser, and the title strip's drag region is
  meaningless in a tab (see [ADR 0023](adr/0023-browser-as-a-second-client.md)). Views
  read it as the `@client` assign, put there by `LocalCentsWeb.Client`.

  Deliberately *not* called a **shell**, which in this repo already means both the
  imperative shell around the functional core
  ([ADR 0014](adr/0014-functional-core-process-shell.md)) and the Tauri container
  (`LocalCentsWeb.DesktopShell`). Nor a **host**, which collides with `conn.host` and
  `PHX_HOST`; nor a **runtime**, which is a Book's resident process
  ([ADR 0007](adr/0007-book-runtime-and-persistence.md)); nor a **viewer**, which is a
  window registered against a `BookServer`.

  Unrelated: "client" in the LiveView sense — the JavaScript half of the socket — is a
  different axis. Both clients here run a browser engine and both have a JS client.

## Asynchronous and synchronous test modules

* **Asynchronous test module** -- a test module declared `async: true`. ExUnit may
  run it concurrently with other asynchronous modules, up to `:max_cases`. Every
  test module in LocalCents strives to be one; the Testing section of
  `CODING_STANDARDS.md` at the repo root is the standard for keeping it that
  way.
* **Synchronous test module** -- a test module declared `async: false`. ExUnit runs
  every synchronous module **after** all asynchronous ones have finished, and runs
  them one at a time, so their cost is the sum of their runtimes rather than the
  longest of them. A module has to be synchronous only when it mutates state
  another concurrently-running test could observe.

Prefer these over "serial" and "parallel", which describe the scheduling rather
than the declaration a module actually makes.
