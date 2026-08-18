# Does Phoenix already provide a field-name → display-label helper?

> Research note behind `LocalCentsWeb.ConflictPresenter.field_label/1`, a
> hand-rolled helper that turns a stored scalar-field name into user-facing
> copy: `"description" → "Description"` and, critically, `"category_id" →
> "Category"` (stripping the `_id` suffix rather than leaking `"Category_id"`).
> The question is whether Phoenix or a bundled library already ships that exact
> transformation so we can drop the hand-rolled version. Sources are primary
> only: the **installed** source under `deps/` for the versions this repo pins,
> plus the doctest examples those modules carry. No blog posts or secondary
> write-ups were used.

## Question

We wrote:

```elixir
def field_label("category_id"), do: "Category"
def field_label(field), do: String.capitalize(field)
```

Is there a built-in that does the same job — capitalize, underscores to spaces,
and strip a trailing `_id` — so the hand-rolled helper (and its one hardcoded
`"category_id"` special case) can go away?

## Answer

**Yes. `Phoenix.Naming.humanize/1` is a drop-in replacement and is strictly
more general than `field_label/1`.** It strips a trailing `_id`, replaces
underscores with spaces, and capitalizes — so it returns `"Category"` for
`"category_id"` **without** the hardcoded special case, and `"Description"` for
`"description"`. It is part of the `phoenix` dependency the repo already pins
(1.8.11), so no new dependency is needed.

The only thing to weigh before swapping is a semantic coupling, not a
correctness gap: `humanize` gives `"Category"` by *mechanically* dropping the
`_id` foreign-key suffix, whereas `field_label/1` says "Category" as a
deliberate domain choice. They agree today on every field we render. See the
recommendation for where that distinction could bite.

The other candidates (`Phoenix.HTML.Form`, core_components `<.input>`, Gettext,
Ecto reflection) do **not** provide this — the current Phoenix stack does not
auto-humanize field names anywhere, so there is no framework label to inherit.

## Per-candidate findings

### 1. `Phoenix.Naming.humanize/1` — the match

Version in use: `phoenix` **1.8.11** (`mix.lock`). Read directly from
`deps/phoenix/lib/phoenix/naming.ex`.

The doctest that ships with the function (lines ~112–121):

```elixir
    iex> Phoenix.Naming.humanize(:username)
    "Username"
    iex> Phoenix.Naming.humanize(:created_at)
    "Created at"
    iex> Phoenix.Naming.humanize("user_id")
    "User"
```

The implementation (lines ~123–135):

```elixir
def humanize(atom) when is_atom(atom),
  do: humanize(Atom.to_string(atom))
def humanize(bin) when is_binary(bin) do
  bin =
    if String.ends_with?(bin, "_id") do
      binary_part(bin, 0, byte_size(bin) - 3)
    else
      bin
    end

  bin |> String.replace("_", " ") |> String.capitalize
end
```

Tracing our three cases through that body:

- `humanize("category_id")` → ends with `_id`, so trimmed to `"category"` →
  `"category"` (no other underscore) → `String.capitalize` → **`"Category"`**.
  Matches our special case exactly, with no special case.
- `humanize("description")` → no `_id` → `"description"` → **`"Description"`**.
- `humanize("user_id")` → trimmed to `"user"` → **`"User"`** (also the shipped
  doctest).

Note `String.capitalize/1` upcases only the first grapheme and downcases the
rest, which is the same trailing behavior as our current `String.capitalize`
branch — e.g. `"created_at" → "Created at"`, not `"Created At"`. So swapping in
`humanize` does not change any label we already produce.

### 2. `Phoenix.HTML.Form` label helpers — no longer humanizes

Version in use: `phoenix_html` **4.3.0** (`mix.lock`). Grepping the entire
installed tree finds **no** `humanize` and no `label`-building helper:

```
$ grep -rln "humanize" deps/phoenix_html/
   (no output)
```

Older `phoenix_html` (2.x/3.x) exposed `Phoenix.HTML.Form.humanize/1` and a
`label/2` that derived text from the field name, but 4.x removed the HTML-tag
and form-label generators. So there is nothing here to reuse, and nothing that
would auto-derive a label from a field name.

### 3. core_components `<.input>` — label is explicit, never derived

Read from `lib/local_cents_web/components/core_components.ex`. The `label`
attribute defaults to nil and is only rendered when passed:

```elixir
attr :label, :string, default: nil
...
<span :if={@label} class="label mb-1">{@label}</span>
```

The `FormField` clause (line 200) copies `id`, `name`, `value`, and `errors`
off the field but does **not** synthesize a label from `field.field`:

```elixir
def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
  errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []
  assigns
  |> assign(field: nil, id: assigns.id || field.id)
  |> assign(:errors, Enum.map(errors, &translate_error(&1)))
  |> assign_new(:name, fn -> ... end)
  |> assign_new(:value, fn -> field.value end)
  |> input()
end
```

So the Phoenix 1.8 generated stack expects the caller to supply the label
string; it offers no humanization we could lean on.

### 4. Gettext — the translation layer, not a source of the base label

Version in use: `gettext` **1.0.2** (`mix.lock`). Gettext answers a different
question: given a base string, return its translation for the current locale.
It does not turn `"category_id"` into `"Category"` — you still need to produce
the base label first (by hand, or via `humanize`). In core_components its only
role for inputs is `translate_error/1` on validation messages, not label
derivation.

Idiomatically, Gettext wraps a label for i18n (`gettext("Category")`); it is
complementary to, not a replacement for, the humanize step. For a
single-locale app like LocalCents today it adds nothing over a plain string.

### 5. Ecto schema/changeset reflection — no human labels

Grep of `deps/ecto/lib/ecto/schema.ex` for `human`/`humanize` returns nothing.
Ecto's reflection API (`__schema__(:fields)`, `:type`, etc.) yields the raw
atom field names and their types, but no display-label facility — confirming
the expectation that Ecto is not the place for this.

### 6. `Phoenix.Naming` siblings — for completeness

From the same file: `resource_name/2`, `unsuffix/2`, `underscore/1`,
`camelize/1,2`. None produce a display label; `humanize/1` is the only member
aimed at "attribute/form field into its humanize version" (its own `@doc`).
`unsuffix/2` is the generic suffix-stripper `humanize` uses conceptually, but
it is case-sensitive and does no spacing/capitalization, so it is not a
shortcut here.

## Recommendation

**Replace `field_label/1` with `Phoenix.Naming.humanize/1`.** It reproduces
every label we emit today, deletes the one hardcoded branch, and adds no
dependency (it is already in `phoenix`). Concretely, `field_label(field)`
becomes `Phoenix.Naming.humanize(field)` at both call sites (the Conflicts tab
view and the Synced changes popup), and the two `field_label` heads plus their
`@doc`/`@spec` can go.

The single judgment call is a coupling of *meaning*, worth one sentence in the
commit or a code comment rather than a blocker:

- `humanize` yields `"Category"` because it mechanically strips the `_id`
  foreign-key suffix. That happens to equal the domain label we want.
- If a future scalar field's column name and its display label ever diverge in
  a way this rule gets *wrong* — e.g. a stored `"paid_by_id"` that should read
  "Paid by" (humanize gives exactly that) versus one where the trimmed word is
  not the word we want to show — we would need a small override map again.

Given the current field set (`description`, `category_id`, and the like),
there is no such divergence, so the mechanical rule and the domain intent
coincide. If you want to keep the intent explicit and cheap to override later,
one option is a thin wrapper that defers to `humanize` for the general case and
keeps a map only for genuine exceptions — but with zero exceptions today, the
bare `humanize/1` call is the simpler choice and the one I recommend.

Anything not called out here is not a gap: the other four candidates simply do
not offer this transformation in the pinned versions.
