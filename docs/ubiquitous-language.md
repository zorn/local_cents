# Ubiquitous Language

The name of the application is `LocalCents`, no space. When represented inside Elixir this is atomized as `:local_cents`.

## Domain Terms

### Tracking (Bounded Context)

* **Book** -- The document that all other main domain entities live inside. As
  the app is starting out we will be recording expenses only for the most part
  but in time we hope to expand towards income and other financial data.
* **Expense** -- A financial transaction that represents money the user has spent.

## UI Terms

We want to take care when presenting terminology inside the user interface. We want to choose our terms with intent and consistency.

### Creating things

Following a macOS norm, we use the term **"New"** when initiating a blank top-level entity from a main menu or a button (e.g., "New Book", "New Expense"). If the creation process requires a form, we then use the term **Create** for a submit-like button label as it is an appropriate and user friendly action verb.

If you are appending a sub-item to an existing entity for example a Tag or an Attachment you can use the verb **Add** (e.g., "Add Tag", "Add Attachment"). These sub-items are part of the identity of the parent Expense, so if you add a new tag then the Expense is considered updated.

### Editing things

Use **"Edit"** to label the action of opening an entity for modification. 

### Deleting things

Use **"Delete"** for permanent removal of an entity. Use **"Remove"** only when detaching an item from a collection without destroying it (e.g., removing a tag from an expense).

### Acting on things

Use **"Open"** when referencing the action of opening a Book in its document window.

## Software Terms

### Structs, Values, and Entities 

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

#### An example: Is an `Address` an entity or a value object? It depends.

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
