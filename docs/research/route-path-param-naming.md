# Naming a route's id path param (`:id` vs `:book_id`)

> Research note behind the path param for the category management route
> (`/books/:book_id/categories`, `LocalCentsWeb.BookCategoriesLive`): should the
> book-id segment be `:id` or `:book_id`? A companion to
> [`params-variable-naming-convention.md`](params-variable-naming-convention.md).
> Sources are primary: the Phoenix routing guide and the `resources` macro's own
> generated routes. No secondary write-ups were used as authorities.

## Question

Our route was `/books/:id/categories`. Is `:id` right, or is `:book_id` more
expressive — and should the router use it?

## What Phoenix does

Phoenix's convention comes straight from the `resources` macro and the routing
guide: **a resource's _own_ id is `:id`; a _parent_ resource's id in a nested
route is `:<parent_singular>_id`.**

From the [Phoenix routing guide](https://phoenix.hexdocs.pm/routing.html), nesting
`posts` under `users` generates:

```
GET  /users/:user_id/posts           PostController :index
GET  /users/:user_id/posts/:id/edit  PostController :edit
```

The parent (`user`) becomes `:user_id`; the child's own id stays `:id`. The guide
notes "each of these routes scopes the posts to a user ID."

## Applying it here

`/books/:.../categories` is **categories scoped under a book** — the book is the
*parent* of that route, not the resource the route acts on. By the nested-resource
convention that segment is a parent id, so its idiomatic name is **`:book_id`**:

```elixir
live "/books/:book_id/categories", BookCategoriesLive
```

This is *not* in tension with `BookLive`'s `/books/:id`. There the book **is** the
resource the route addresses, so `:id` is correct. The two together mirror
`/users/:id` (a user) vs `/users/:user_id/posts` (posts of a user) exactly — same
book, two roles, two conventional names.

## Decision

Use **`:book_id`** for the book segment of the category route, and match it in
`mount/3` (`%{"book_id" => book_id}`). It reads as the parent-scope id it is, and
distinguishes it at a glance from the category `id` the page's event handlers
carry. `BookLive` keeps `:id`. `~p` sitemap paths are positional, so they were
unaffected by the rename.
