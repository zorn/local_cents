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
