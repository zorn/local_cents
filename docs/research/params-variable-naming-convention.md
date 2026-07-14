# Naming the params variable (`params` vs `<resource>_params`)

> Research note behind a naming choice in `LocalCentsWeb.BookLive` and
> `LocalCentsWeb.BookCategoriesLive`: what to call the variable bound out of a
> form's params map in `handle_event` — the generic `params`, or a descriptive
> `expense_params` / `category_params`. Sources are primary: the **installed**
> Phoenix generator templates under `deps/phoenix/priv/templates/`, the Phoenix and
> Phoenix.LiveView HexDocs, and Elixir Forum threads. No secondary write-ups were
> used as authorities.

## Question

Our event handlers pattern-match the form payload, e.g.:

```elixir
def handle_event("save_category", %{"category" => params}, socket) do
  save_category(socket, socket.assigns.editing, params)
end
```

Should the binding be the generic `params`, or the descriptive `category_params`?
The map **key** (`"category"`) is not a choice — `phoenix_ecto` derives it from the
schema's form name — so only the variable name is in play.

## What Phoenix itself does

**The generators emit `<resource>_params` when they destructure a form map, and
bare `_params` for an ignored or whole payload.** Straight from the installed
templates:

- `deps/phoenix/priv/templates/phx.gen.html/controller.ex.eex`:
  ```elixir
  def create(conn, %{<%= inspect schema.singular %> => <%= schema.singular %>_params}) do
    case ...create_<%= schema.singular %>(<%= ... %><%= schema.singular %>_params) do
  ```
  and the same for `update`. For a `User` schema this renders
  `def create(conn, %{"user" => user_params})`.
- The **LiveView** generator agrees — `deps/phoenix/priv/templates/phx.gen.auth/registration_live.ex.eex`:
  ```elixir
  def handle_event("save", %{"<%= schema.singular %>" => <%= schema.singular %>_params}, socket) do
  ```
- The same controller template uses the plain, underscored form for payloads it
  ignores or doesn't destructure: `def index(conn, _params)`, `def new(conn, _params)`,
  and `mount(_params, _session, socket)`.

So the community convention, baked into the tool everyone starts from, is:

| Situation | Name |
|---|---|
| Destructured resource params (`%{"user" => …}`) | `user_params` (`<singular>_params`) |
| Whole/ignored event or mount payload | `params` / `_params` |

**Docs corroborate.** The [Phoenix.LiveView docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
name the *whole* `handle_event` payload `params` (before any destructuring); the
[Phoenix Controllers guide](https://phoenix.hexdocs.pm/controllers.html) pattern-matches
resource params in the function head. The Elixir Forum threads on the topic
([params key name](https://elixirforum.com/t/convention-for-params-key-name/1662),
[how `%{"user" => user_params}` works](https://elixirforum.com/t/in-phoenix-how-does-this-work-user-user-params/13328))
treat the descriptive `<resource>_params` binding as settled, not debated.

## Decision

Use **`<resource>_params`** for the value destructured out of a form map, and keep
bare **`_params`** for the whole/ignored payload — matching the generators.

- `BookCategoriesLive`: `%{"category" => category_params}` in `save_category` /
  `validate_category`, threaded through the private `save_category/3` clauses.
- `BookLive`: `%{"expense" => expense_params}` in `save_expense` /
  `validate_expense`, threaded through `save_expense/3` and `invalid/4`.
- Ignored payloads stay `_params` (`new_category`, `cancel_edit`, `open_categories`, …).

This aligns both mirror LiveViews with the ecosystem convention and with each other.
The generic changeset builders (`category_form/3`, `editor_form/4`) keep their own
formal parameter name — they're not the event binding.
