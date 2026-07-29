# Making an `on_mount` Contract Visible From the Views That Depend On It

> Research note feeding [issue #181](https://github.com/zorn/local_cents/issues/181) — `LocalCentsWeb.BookWindow`'s `on_mount` hook opens a Book's runtime, subscribes, registers a viewer, and assigns `:book`/`:page_title`, but it is attached in the router's `:book_window` `live_session`. From inside `BookLive`, `BookCategoriesLive`, or `BookReportLive` there is no local evidence any of that happened — only a prose comment maintained in triplicate and a bare `socket.assigns.book`. Raised by the maintainer in review of [PR #174](https://github.com/zorn/local_cents/pull/174): "these `on_mount` hooks are attached in the router and thus here in the LiveView module there is an unknown / unseen contract we have to comment to document and that feels brittle and duplicative. How else might we approach this situation?"
>
> Primary sources: this repo's own source, cited by `path:line`; the vendored Phoenix LiveView source at `deps/phoenix_live_view` (v1.2.7) — `phoenix_live_view.ex`, `phoenix_live_view/router.ex`, `lifecycle.ex`, `channel.ex`, `static.ex`, `session.ex`, `route.ex`; the vendored `phx.gen.auth` templates at `deps/phoenix/priv/templates/phx.gen.auth/`; and the *source* (not write-ups about it) of Livebook, Plausible, Firezone, Ash Authentication Phoenix, Backpex, Oban Web, Phoenix LiveDashboard, PhoenixStorybook, Ash Admin, Beacon LiveAdmin, LiveAdmin, Bonfire, Sequin, and NervesHub. Three probe scripts were run against this repo's exact LiveView build, and their output is quoted where it is load-bearing.
>
> No blog or forum sources were used. The framework source settles the mechanics outright, and the ecosystem question is answered by reading the projects.
>
> **Status:** research complete, nothing applied. Written against `main` at `e374fec`.

## 1. What is actually true in this repo today

The hook is 81 lines with a thorough moduledoc (`lib/local_cents_web/book_window.ex:1`–`:20`) and one public callback:

```elixir
@spec on_mount(:default, params :: map(), session :: map(), Socket.t()) ::
        {:cont, Socket.t()} | {:halt, Socket.t()}
def on_mount(:default, %{"book_id" => book_id}, _session, socket) do
  with :ok <- Tracking.open_book(book_id),
       %Tracking.Book{} = book <- fetch_book(socket, book_id) do
    {:cont, assign(socket, book: book, page_title: book.name)}
```

(`lib/local_cents_web/book_window.ex:32`–`:41`.) On a connected mount `fetch_book/2` also calls `Tracking.subscribe/1` and `Tracking.register_viewer/1` (`:57`–`:64`); the latter is the load-bearing one, because presence registration is what keeps the `BookServer` resident (`docs/book-runtime-lifecycle.md:11`–`:18`).

It is attached once, in the router (`lib/local_cents_web/router.ex:37`–`:41`):

```elixir
live_session :book_window, on_mount: {LocalCentsWeb.BookWindow, :default} do
  live "/books/:book_id", BookLive
  live "/books/:book_id/categories", BookCategoriesLive
  live "/books/:book_id/report", BookReportLive
end
```

And the three views each carry a hand-maintained restatement of it:

- `lib/local_cents_web/live/book_live.ex:31`–`:33`
- `lib/local_cents_web/live/book_categories_live.ex:28`–`:30`
- `lib/local_cents_web/live/book_report_live.ex:46`–`:48`

plus a fourth and fifth copy in the two moduledocs that describe the mount contract in prose (`book_categories_live.ex:8`–`:11`, `book_report_live.ex:8`–`:10`) and a sixth in the router comment (`router.ex:33`–`:36`). The maintainer's drift prediction is already evidenced: the hook's behaviour changed twice inside PR #174 (a `register_viewer/1` failure path, then returning the Book from the runtime instead of re-reading disk), and each change required touching the comments by hand.

Existing enforcement: one integration test, `test/local_cents_web/book_window_test.exs:23`, mounts `~p"/books/#{book.id}"` and asserts a viewer appears in `Presence` and that the server reaps on disconnect. It proves the *hook* works. It says nothing about whether a **future** view is inside the `live_session`.

ADR 0017 predicted this shape and pre-authorised the extraction — `docs/adr/0017-in-window-secondary-views.md:53`–`:56` lists it under "Carried forward": "each page re-establishes its own `open_book`/`subscribe` contract, so the per-page mount boilerplate is duplicated rather than shared — acceptable now, and a candidate for a small `on_mount` hook if the view count grows." The hook exists now; the ADR has not been updated to say where it attaches or what keeps that true.

## 2. What the framework does and does not enforce

This section is the bound on how bad the failure mode really is. Every claim is from the vendored LiveView source.

### 2.1 The two attachment points are additive, in a fixed order

A `live_session`'s `:on_mount` list is validated and stored in the session's `extra` map (`deps/phoenix_live_view/lib/phoenix_live_view/router.ex:303`–`:310`), which `__live__/4` then stamps into every enclosed route's metadata as `{live_view, action, opts, live_session}` (`:360`–`:391`). A module's own `on_mount/1` declarations accumulate in the `@phoenix_live_mount` attribute and are baked into `__live__()` at `@before_compile` (`deps/phoenix_live_view/lib/phoenix_live_view.ex:603`–`:626` and `:451`–`:459`).

They are combined at mount time by prepending the router's:

```elixir
defp load_lifecycle(
       %{lifecycle: lifecycle},
       %Route{live_session: %{extra: %{on_mount: on_mount}}}
     ) do
  update_in(lifecycle.mount, &(on_mount ++ &1))
end
```

(`deps/phoenix_live_view/lib/phoenix_live_view/channel.ex:1303`–`:1307`; the identical merge for the dead render is `static.ex:312`–`:314`.) So `live_session` hooks always run **before** module-declared hooks, and both run.

### 2.2 There is no deduplication — belt-and-braces double-runs the hook

`Lifecycle.prepare_on_mount!/1` is a bare comprehension with no uniqueness check (`deps/phoenix_live_view/lib/phoenix_live_view/lifecycle.ex:142`–`:146`):

```elixir
def prepare_on_mount!(hooks) do
  for {module, _fun} = id <- hooks do
    hook!(id, :mount, Function.capture(module, :on_mount, 4))
  end
end
```

Verified against this repo's build with a probe script that defined a `use`-macro injecting `on_mount {Probe.Hook, :default}` and applied it twice:

| Module | `__live__().lifecycle.mount` |
|---|---|
| plain LiveView | `[]` |
| `use Probe.UseMacro` once | one hook |
| `use Probe.UseMacro` twice | **two identical hooks**, same `id` |
| router hooks `++` module hooks | 2 entries, `[{LocalCentsWeb.BookWindow, :default}, {Probe.Hook, :default}]` |

This matters concretely for LocalCents. `BookServer.register_viewer/1` is `Presence.track(self(), presence_topic(id), inspect(self()), %{})` (`lib/local_cents/tracking/book_server.ex:299`–`:305`), and tracking the same pid under the same key twice returns `{:error, {:already_tracked, pid, topic, key}}` (`deps/phoenix_pubsub/lib/phoenix/tracker/shard.ex:249`). That lands in `BookWindow`'s error branch, which `Logger.error`s and falls back to a disk read (`lib/local_cents_web/book_window.ex:71`–`:80`). **Keeping the router attachment *and* adding a module-level one is not a harmless safety net here — it produces a logged error on every mount.** Any "make it local" option must therefore be a *move*, not an addition.

### 2.3 `use Phoenix.LiveView` accepts no `:on_mount` option

The `__using__/1` doc lists exactly four options — `:container`, `:global_prefixes`, `:layout`, `:log` (`deps/phoenix_live_view/lib/phoenix_live_view.ex:400`–`:424`). The only module-level mechanism is the `on_mount/1` macro, which is `import`ed by `use Phoenix.LiveView` (`:438`). A `use LocalCentsWeb.BookWindow` macro would therefore have to expand to that macro call and must be placed *after* `use LocalCentsWeb, :live_view`.

### 2.4 Being in the wrong `live_session` never raises. It logs, at most

This is the important bound. LiveView checks `live_session` membership in three places, and none of them is a compile-time or mount-time failure:

1. **Server-initiated `push_navigate` / `<.link navigate>` across sessions** — `Session.authorize_root_redirect/2` returns `:error` when the target route's `live_session` name differs (`deps/phoenix_live_view/lib/phoenix_live_view/session.ex:19`–`:30`), and the channel turns that into a warning plus a full page reload (`channel.ex:1623`–`:1635`):

   ```elixir
   Logger.warning(
     "navigate event to #{inspect(url)} failed because you are redirecting across live_sessions. " <>
       "A full page reload will be performed instead"
   )
   ```

2. **Reconnect after a deploy moved the view** — `authorize_session/3` falls back to a full page redirect with no log at all (`channel.ex:1647`–`:1665`).

3. **`handle_params` / patch resolution** — `Route.live_link_info!/3` reclassifies a same-view-different-session match as `{:external, route.uri}` (`route.ex:32`–`:38`), i.e. a full navigation.

So if a fourth document-window view were added outside `:book_window`, the app would still compile, still mount, and still render. The only in-band signal is a `Logger.warning` on the *navigation into it* from `BookLive` — and `BookLive` reaches the sibling views precisely that way (`lib/local_cents_web/live/book_live.ex:208`, `:215`). That is a real but weak detector: log-level only, triggered by navigation rather than by a fresh window, and silent for a view opened directly by URL (which on the desktop is exactly how Rust opens a document window — ADR 0006). Meanwhile `Tracking.register_viewer/1` is never called, so the `BookServer` reaps out from under an open window after the grace period.

The failure mode is therefore: **compiles, renders, looks correct, and quietly forfeits the lifecycle guarantee the hook was extracted to enforce.**

### 2.5 The framework's own advice is "put it in the right `live_session`", enforced by documentation

`phx.gen.auth` is the canonical hook-plus-`live_session` pattern in the ecosystem, and it is vendored here. Its generated `UserAuth` moduledoc explicitly offers **both** attachment points as equals (`deps/phoenix/priv/templates/phx.gen.auth/auth.ex.eex:198`–`:213`):

```
Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
the `current_scope`:

    defmodule MyAppWeb.PageLive do
      use MyAppWeb, :live_view

      on_mount {MyAppWeb.UserAuth, :mount_current_scope}
      ...
    end

Or use the `live_session` of your router to invoke the on_mount callback:

    live_session :authenticated, on_mount: [{MyAppWeb.UserAuth, :require_authenticated}] do
      live "/profile", ProfileLive, :index
    end
```

The generated router uses the `live_session` form (`routes.ex.eex:14`–`:18`, `:30`–`:35`). And Phoenix's answer to "what keeps a new LiveView in the right session?" is, remarkably, **a generated `AGENTS.md`** (`deps/phoenix/priv/templates/phx.gen.auth/AGENTS.md.eex`):

> "LiveViews that require login should **always** be placed inside the __existing__ `live_session :require_authenticated_user` block" (`:20`)
>
> "**Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**" (`:11`)
>
> "Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug and `live_session`**" (`:16`)

That is the state of the art from the framework itself: prose, in a file aimed at coding agents, with no compile-time or test-time check anywhere. It also shows Phoenix arrived at the same problem statement as issue #181 — the third bullet is the user-facing symptom of exactly this class of mistake.

Note *why* the AGENTS.md rule can be phrased as "the existing block": the one compile-time guarantee LiveView does provide is **uniqueness of a session name, not membership in it** (`deps/phoenix_live_view/lib/phoenix_live_view/router.ex:244`–`:256`):

```elixir
if nested = Module.get_attribute(module, :phoenix_live_session_current) do
  raise """
  attempting to define live_session #{inspect(name)} inside #{inspect(nested.name)}.
  live_session definitions cannot be nested.
  """
end

if name in Module.get_attribute(module, :phoenix_live_sessions) do
  raise """
  attempting to redefine live_session #{inspect(name)}.
  live_session routes must be declared in a single named block.
  """
end
```

Because `live_session :book_window` can only be written once, "put it in the existing block" is at least a checkable instruction for a human. It is not a check the compiler performs on the LiveView.

`phx.gen.auth` does, however, answer the *other* half of the issue. It does not leave the hook's output as a loose assign: it introduces a dedicated struct, `MyApp.Accounts.Scope`, with its own module and moduledoc (`scope.ex.eex:1`–`:33`), and the generated `AGENTS.md` states the access rule once, centrally (`AGENTS.md.eex:12`–`:14`): "`phx.gen.auth` assigns the `current_scope` assign — it **does not assign a `current_user` assign** … To derive/access `current_user` in templates, **always use the `@current_scope.user`**." One named type, one documented access path, no per-view comment.

## 3. Survey — what real projects actually do

Three applications were read in full from source clones (Livebook, Plausible, Firezone), several libraries were read from the copies vendored into this repo's `deps/`, and a GitHub-wide code search located the remaining patterns, each verified by opening the file. Supabase Realtime and changelog.com were checked and dropped: Realtime has two LiveViews and no `on_mount`, and changelog.com defines no `live` routes at all.

Nine distinct approaches turned up. They are not alternatives to each other — the strong codebases stack two or three.

| # | Approach | Distinct projects seen | Named exemplars |
|---|---|---|---|
| A | Router `live_session` + prose only (the status quo here) | ubiquitous | Firezone, `phx.gen.auth` output, Livebook's auth hooks |
| B | Module-level `on_mount` in the LiveView body | 5+ | **Livebook** (8 views), Qlarius, Bonfire, region-manager |
| C | `use MyAppWeb, :live_view` injects the hook via `__using__` | 6+ | **Plausible** (3 hooks), techschool.dev |
| D | A router macro that emits the `live_session` *and* the routes | 6 | **LiveDashboard**, **PhoenixStorybook**, Oban Web, Ash Authentication Phoenix, Ash Admin, Beacon LiveAdmin |
| E | Hook-set assigns appear in `mount/3` / `render/1` **guards** | 1 | **Livebook** `AppLive`, `AppSessionLive` |
| F | Hook-set assigns funnelled through a component with `attr … required: true` | 3 | **Livebook** `Layouts.layout/1`, Backpex, Firezone |
| G | Prerequisite assigns destructured at the top of a downstream hook | 4 | **Firezone**, **Oban Web**, NervesHub, LiveAdmin |
| H | An accessor function instead of `socket.assigns.foo` | 4 | **Sequin** `LiveHelpers.current_user/1` |
| I | A test that reads the router table and asserts `live_session` membership | 8 | **Ash Authentication Phoenix**, kanban, rule_maven, acai-sh/server; Beacon and Oban Web for their own macros |

And two things **nobody** does, searched for explicitly and not found:

- **No project defines a `@type` or struct describing "the assigns this hook guarantees."** `phx.gen.auth`'s `Scope` struct types the *value* an assign holds, not the bundle a hook provides. Livebook, Plausible, and Firezone all read `socket.assigns.subject` / `@current_user` bare.
- **No project checks at compile time that a LiveView is inside a given `live_session`.** `@after_compile` + `on_mount` returns no genuine hit. LiveView exposes `:live_session_name` in route metadata, and the only readers of it are the tests in row I and one dev-tools route inspector.

### 3.1 B — declare the hook in the view that needs it (Livebook)

Livebook is the closest structural analogue to LocalCents: many concurrently-open, session-scoped LiveViews over a per-document runtime process, with a `register_client/3` call that LocalCents' own `Tracking.register_viewer/1` doc already cites as prior art (`lib/local_cents/tracking.ex:576`).

It **splits its hooks by kind.** The router carries the cross-cutting ones (`lib/livebook_web/router.ex:73`–`:75`):

```elixir
live_session :default,
  on_mount: [LivebookWeb.UserHook, LivebookWeb.AuthHook, LivebookWeb.Confirm],
  session: {LivebookWeb.UserPlug, :extra_lv_session, []} do
```

But the hook whose assigns a view *renders* is declared in the view. `LivebookWeb.SidebarHook` appears on exactly eight LiveView modules, one line each, immediately under `use LivebookWeb, :live_view` (`lib/livebook_web/live/home_live.ex:6`, `session_live.ex:12`, `learn_live.ex:9`, `settings_live.ex:4`, `open_live.ex:8`, `apps_dashboard_live.ex:6`, `hub/edit_live.ex:7`, `hub/new_live.ex:7`):

```elixir
defmodule LivebookWeb.HomeLive do
  use LivebookWeb, :live_view

  import LivebookWeb.SessionHelpers

  on_mount LivebookWeb.SidebarHook
```

`LivebookWeb.live_view/0` injects nothing (`lib/livebook_web.ex:14`–`:20` is a bare `use Phoenix.LiveView` plus helpers). The dividing line Livebook draws is instructive: **hooks that gate access live in the router; hooks a view depends on to render live in the view.** LocalCents' hook is the second kind.

### 3.2 C — a `use` macro that injects `on_mount` (Plausible)

Plausible implements issue #181's first candidate direction directly, and stacks three of them. `lib/plausible_web/live/auth_context.ex:13`–`:17`:

```elixir
defmacro __using__(_) do
  quote do
    on_mount unquote(__MODULE__)
  end
end
```

wired into the app-wide LiveView macro (`lib/plausible_web.ex:6`–`:21`):

```elixir
def live_view(opts \\ []) do
  quote do
    use Plausible
    use Phoenix.LiveView, global_prefixes: ~w(x-)
    use PlausibleWeb.Live.Flash

    use PlausibleWeb.Live.AuthContext

    unless :no_sentry_context in unquote(opts) do
      use PlausibleWeb.Live.SentryContext
    end
```

Two details worth stealing. First, the hook body is `assign_new/3` throughout, which is what makes the declaration idempotent and therefore safe to repeat. Second, `SentryContext`'s moduledoc documents an explicit **opt-out** — `use PlausibleWeb, live_view: :no_sentry_context` — for nested LiveViews that have no `connect_info`. Plausible then keeps the router's `live_session`s for what is genuinely route-scoped: `:auth`, `:settings`, `:customer_support` (`lib/plausible_web/router.ex:113`, `:425`, `:496`).

### 3.3 D — the router macro carries the `live_session` (the library answer)

Every LiveView library that ships mountable pages solves this the same way, and two of them are vendored in this repo. `live_dashboard/2` expands to a `scope` containing a `live_session` and the routes together (`deps/phoenix_live_dashboard/lib/phoenix/live_dashboard/router.ex:104`–`:116`, options assembled at `:324`–`:331`):

```elixir
import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

live_session session_name, session_opts do
  get "/css-:md5", Phoenix.LiveDashboard.Assets, :css, as: :live_dashboard_asset
  ...
  live "/", Phoenix.LiveDashboard.PageLive, :home, route_opts
  live "/:page", Phoenix.LiveDashboard.PageLive, :page, route_opts
end
```

`live_storybook/2` does the same, emitting two `live_session`s and pinning `on_mount: PhoenixStorybook.Mount` (`deps/phoenix_storybook/lib/phoenix_storybook/router.ex:90`–`:106`, `:145`–`:149`). This repo's own router already consumes that macro at `lib/local_cents_web/router.ex:43` — the `:live_storybook` and `:live_storybook_iframe` sessions in the route table are not written by hand.

The property is the one issue #181 wants: **a route cannot be declared outside the session, because declaring the route and declaring the session are the same act.**

PhoenixStorybook's mount hook also shows the fail-loud posture on the *other* end of the contract (`deps/phoenix_storybook/lib/phoenix_storybook/mount.ex:6`–`:14`) — every value it pulls out of the session is `Map.fetch!/2`, so a misconfigured session raises rather than assigning `nil`.

### 3.4 E and F — put the hook's assigns in a signature (Livebook)

The single strongest "the contract is visible from the view" technique found anywhere is Livebook's, and it is startlingly cheap: **guard on the hook-set assign in the `mount/3` and `render/1` heads** (`lib/livebook_web/live/app_live.ex:6`, `:14`, `:43`; same shape in `app_session_live.ex` and `app_auth_live.ex`):

```elixir
@impl true
def mount(%{"slug" => slug}, _session, socket) when not socket.assigns.app_authenticated? do
  ...
end

def mount(%{"slug" => slug}, _session, socket) when not socket.assigns.app_authorized? do
  ...
end

@impl true
def render(assigns) when assigns.app_authenticated? and assigns.app_authorized? do
```

The hook's output is now part of the function signature. A view mounted without `AppAuthHook` has no matching `render/1` clause and raises. No comment required.

Livebook's second mechanism is a shared layout component whose `attr` list is the documented shape of everything the hooks must produce (`lib/livebook_web/components/layouts.ex:44`–`:53`):

```elixir
attr :flash, :map, required: true, doc: "the map of flash messages"
attr :confirm_state, :map, required: true
attr :current_page, :string, required: true
attr :current_user, Livebook.Users.User, required: true
attr :teams_auth, :atom, values: [:online, :offline]
attr :saved_hubs, :list, required: true
attr :notifications, :list, required: true
```

`attr :current_user, Livebook.Users.User` is the only struct-typed hook assign found in the entire survey. Every view passes these explicitly at the call site, so the layout invocation is a per-view restatement of the contract that the compiler partly checks.

Backpex does the same with one attribute and it is the *only* enforcement its own `InitAssigns` hook has: `attr :current_url, :string, required: true` on the component that consumes it (`lib/backpex/html/resource.ex`), where `current_url` is set by nothing but that hook. A missing hook is then a `KeyError` at render rather than a wrong-looking sidebar. Cheap, declarative, and machine-readable — the least-effort item on this whole list.

### 3.5 G — make hook ordering a match error (Firezone, NervesHub)

Firezone's hooks form a chain — `FetchAccount` → `FetchSubject` → `EnsureAuthenticated` → `EnsureAdmin` — and each one asserts its predecessor by pattern-matching the struct in the `on_mount/4` head. `elixir/lib/portal_web/live_hooks/ensure_admin.ex:5`–`:16`:

```elixir
def on_mount(
      :default,
      _params,
      _session,
      %{assigns: %{subject: %Subject{actor: %Actor{type: :account_admin_user}}}} = socket
    ) do
  {:cont, socket}
end

def on_mount(:default, _params, _session, _socket) do
  raise PortalWeb.LiveErrors.NotFoundError
end
```

NervesHub does the same one-liner version — `%{org: org} = socket.assigns` as the first line of `mounts/fetch_product.ex` — so a missing predecessor is a `MatchError` at the right frame instead of a `nil` three layers downstream. Oban Web applies it to the *session* rather than the assigns, asserting that its router macro's `session:` MFA actually ran (`oban-bg/oban_web`, `lib/oban/web/authentication.ex:9`–`:10`):

```elixir
def on_mount(:default, params, session, socket) do
  %{"oban" => oban, "resolver" => resolver, "user" => user} = session
```

This enforces *hook ordering* and *hook inputs*, not *view membership*, so it does not solve #181 on its own; it is the cheapest available guard on a contract between hooks. Its mirror image is worth naming as the anti-pattern: Ash Authentication Phoenix's `SignInLive` deliberately tolerates a missing hook — `assign_new(:otp_app, fn -> nil end)`, `session["path"] || "/"` — which is a defensible choice for a white-label view a stranger will mount, and is exactly the choice that produces silent misbehaviour when it is not.

### 3.6 H — an accessor over the assign (Sequin)

Issue #181's third direction has a clean exemplar in Sequin (`lib/sequin_web/live_helpers.ex`):

```elixir
@spec current_user(Socket.t()) :: User.t() | nil
def current_user(socket) do
  socket.assigns.current_user.impersonating_user || socket.assigns.current_user
end
```

It is `@spec`'d, greppable, imported into the views, and — the reason it exists — it is where the derivation logic (impersonation) lives, so callers cannot get it wrong. That is worth naming precisely: **the accessor earns its keep when it does something, not merely when it renames `socket.assigns.x`.** It documents the shape of the value; it does not make the hook's execution any more certain, since a missing assign is still a `KeyError` inside the accessor rather than at the call site.

### 3.7 I — a router-table test (the only real enforcement found anywhere)

Eight repositories read the compiled router table and assert `live_session` wiring. The mechanism is uniform: `Router.__routes__()` (or `Phoenix.Router.routes/1` / `route_info/4`) → `route.metadata.phoenix_live_view` → `{view, action, opts, live_session}` → `live_session.name` and `live_session.extra.on_mount`, whose entries carry an `:id` of `{Module, :hook_arg}`.

The best-sourced instance is a maintained library, `team-alembic/ash_authentication_phoenix` (81 stars, `test/router_test.exs`):

```elixir
test "sign_in_route registers on_mount hooks and layout given as options" do
  route =
    AshAuthentication.Phoenix.Test.Router
    |> Phoenix.Router.routes()
    |> Enum.find(&(&1.path == "/sign-in-on-mount"))

  {_, _, _, %{extra: extra}} = route.metadata.phoenix_live_view

  assert Enum.any?(
           extra.on_mount,
           &(&1.id == {AshAuthentication.Phoenix.Test.OnMountHook, :default})
         )

  assert extra.layout == {AshAuthentication.Phoenix.Test.HomeLive, :live}
end
```

That asserts a *route* carries a *specific hook id* — precisely #181's "nothing enforces the attachment," inverted into a test. Beacon, Oban Web, and LiveDashboard have equivalents.

The application-side variants go one step further, and the one closest to #181 is `cheezy/kanban`, `test/kanban_web/security_invariants_test.exs`:

```elixir
defp live_session_for_path(path) do
  route = KanbanWeb.Router |> Phoenix.Router.routes() |> Enum.find(&(&1.path == path))
  assert route, "no route found for #{path} — did the settings route path change?"

  {_view, _action, _opts, live_session} = route.metadata.phoenix_live_view
  on_mount_ids = Enum.map(live_session.extra.on_mount, & &1.id)

  {live_session.name, on_mount_ids}
end
```

and `joshrieken/rule_maven` has the *completeness sweep* variant, which is the shape that catches a newly added view rather than a moved existing one — iterate every route under a path prefix and assert each one's view is in the expected set. That sweep is the shape LocalCents wants, because #181's stated fear is a *fourth* view, not a moved third.

Two honest caveats.

- **The application-side sample is thin.** Those instances cluster in very-low-star repositories (kanban 5 stars, rule_maven 0, barkpark 2) whose prose carries the texture of AI-assisted codebases. The well-sourced confirmations are all *libraries asserting the hook list their own router macro emits*, which is a narrower claim than "our app's views are correctly gated." For LocalCents the distinction mostly dissolves — this repo owns both the router and the views — but the technique should be adopted as "a good idea with a working library precedent," not "standard practice in mature Elixir apps," because it is not the latter.
- **It reads private internals.** `route.metadata.phoenix_live_view` and `live_session.extra.on_mount[].id` are undocumented LiveView implementation details (`deps/phoenix_live_view/lib/phoenix_live_view/router.ex:391` builds the tuple; `lifecycle.ex:142` builds the hook maps). A LiveView upgrade could change either shape. That is a loud, cheap failure rather than a hazard, but it should be a known cost.

Verified against this repo, the metadata is exactly as described:

```
{"/books/:book_id", LocalCentsWeb.BookLive, :book_window, [:on_mount]}
{"/books/:book_id/categories", LocalCentsWeb.BookCategoriesLive, :book_window, [:on_mount]}
{"/books/:book_id/report", LocalCentsWeb.BookReportLive, :book_window, [:on_mount]}
```

with each route's `live_session.extra.on_mount` holding a single hook whose `id` is `{LocalCentsWeb.BookWindow, :default}`. A drift test here is roughly fifteen lines.

### 3.8 Two structural escapes that dissolve the problem

Three of the surveyed libraries never face this question, because they removed the plural:

- **One LiveView, many page modules.** LiveDashboard routes all three of its paths to a single page LiveView (`deps/phoenix_live_dashboard/lib/phoenix/live_dashboard/router.ex:112`–`:114`); the "pages" are `@behaviour Phoenix.LiveDashboard.PageBuilder` modules, and `use PageBuilder` injects the behaviour but **no `on_mount`**. Oban Web (`DashboardLive`) and Beacon LiveAdmin (`PageLive`) do the same. With one LiveView the contract cannot drift. LocalCents deliberately went the other way — ADR 0017 rejected folding the secondary views into `BookLive` as `live_action`s (`docs/adr/0017-in-window-secondary-views.md:44`–`:46`) — so this is closed, but it is worth knowing it is what the libraries chose.
- **Generate the LiveViews.** Backpex's `use Backpex.LiveResource` `defmodule`s three LiveViews per resource and calls `on_mount` inside each (`lib/backpex/live_resource.ex:335`–`:366`), so a resource cannot exist without its hooks. The honest footnote: **Backpex's own `Backpex.InitAssigns` hook is not injected this way.** It is documented prose telling the user to write `live_session :default, on_mount: Backpex.InitAssigns` in their router. Backpex has issue #181's exact bug for its own hook and did not fix it.

### 3.9 The cost nobody advertises: nested LiveViews do not get router hooks

A `live_render`ed or sticky LiveView is not routed, so a `live_session`'s `on_mount` never reaches it. LiveAdmin's nested nav LiveView shows the consequence (`tfwright/live_admin`, `lib/live_admin/components/nav/wrapper.ex:4`–`:33`): it takes no hook at all and instead rebuilds its whole context inside `mount/3` — strict-destructuring an explicit `session:` map, subscribing to PubSub itself, and assigning eleven keys by hand.

This is an argument, independent of everything else, for keeping the *work* in a plain function that both the hook and any future nested path can call — Backpex puts its PubSub subscribe in a shared `maybe_subscribe_to_pubsub/1` invoked from a generated `mount/3`, not in a hook (`lib/backpex/live_resource.ex`) — rather than only in the hook body. LocalCents has no nested LiveViews today and `BookWindow`'s body is thin enough that this is a note, not a task.


### 3.10 Coverage, and what the searches did not find

Read from source and reported above: Livebook, Plausible, Firezone, Ash Authentication Phoenix, Backpex, Oban Web, LiveAdmin, Bonfire, Sequin, NervesHub, plus the vendored LiveDashboard, PhoenixStorybook, and `phx.gen.auth` templates. Ash Admin and Beacon LiveAdmin were read and match the LiveDashboard router-macro shape exactly, so they are counted but not quoted.

Checked and dropped, with reasons: **Supabase Realtime** has two LiveViews and no `on_mount`; **changelog.com** carries the LiveView dependency but declares no `live` routes; **Mobilizon** is a Vue/GraphQL frontend — code search for both `on_mount` and `live_session` returns zero hits; **Cannery** could not be reached (`gh api repos/shibaobun/cannery` 404s — moved or private).

Searches that returned nothing useful, which is itself part of the answer:

- **`@after_compile` combined with `on_mount`** — no genuine hit. Nobody verifies at compile time that a LiveView is reachable only through a particular `live_session`.
- **`defstruct` describing hook-provided assigns** — no hit. `phx.gen.auth`'s `Scope` and LiveDashboard's `%PageBuilder{}` are containers for a value, not declarations of a hook's output contract.
- **`Map.fetch!(socket.assigns, …)` as a deliberate "assert the hook ran" idiom** — no hit; every occurrence found was unrelated. `Map.fetch!` on the *session* (Storybook, Oban Web) is common; on assigns it is not.
- **`:live_session_name` read from anywhere other than a test** — no hit. Every occurrence is a library router option, plus one dev-tools route inspector.
- **A custom "hook did not run" exception** — no hit in any project.

## 4. Weighing the options against this codebase

Three facts about LocalCents specifically change the arithmetic, and two of them contradict assumptions in the issue.

**The `live_session` here governs nothing but the hook.** `live_session :book_window` is declared with `on_mount:` and nothing else (`lib/local_cents_web/router.ex:37`), which the route table confirms — the session's `extra` map has exactly one key, `[:on_mount]`. There is no `:root_layout`, no `:layout`, no `:session`, and the app has no authentication at all. So issue #181's stated cost of the `use`-macro direction — "costs the `live_session` grouping, which also governs auth/layout" — **does not apply here.** Every library in the survey bundles `on_mount` with `session:` and `root_layout:` because *they* need to; this session does not.

The one thing the named session does buy is soft-navigation cohesion: `push_navigate` between the three views stays on the socket, while `push_navigate(to: ~p"/library")` from a document window (`book_live.ex:587`, `book_categories_live.ex:412`, `book_report_live.ex:210`) crosses into the unnamed `:default` session and is therefore already a full page reload with a `Logger.warning` (Framework section, point 2.4). Removing the hook from the session does not change that; removing the *session* would.

**Belt-and-braces is not available.** Because LiveView deduplicates nothing (2.2) and `Presence.track/4` rejects a repeat of the same pid under the same key, attaching in both places produces a `Logger.error` on every mount. Any "make it local" move must delete the router attachment. That is a genuine sharp edge worth recording wherever the decision lands.

**The failure mode is quiet but not silent.** LiveView never raises on wrong-session membership (2.4); the loudest in-band signal is a warning on navigation *into* the misplaced view. On the desktop, a document window is opened by URL from Rust (ADR 0006), so the first mount of a new window produces no signal at all.

With that, the four directions in the issue:

| Direction | Makes the contract visible? | Enforces it? | Cost here |
|---|---|---|---|
| `use LocalCentsWeb.BookWindow` macro | yes | no | a macro layer that saves nothing over a bare `on_mount` call |
| Router attachment + drift test | no | **yes** | ~15 lines of test reading `@doc false` internals |
| `BookWindow.book(socket)` accessor | marginally | no | indirection with no derivation behind it |
| Centralize the comment | partly | no | free |

The survey's verdict is that the first two are complements, not alternatives — Livebook does the first, Ash Authentication Phoenix does the second, and neither substitutes for the other. The third and fourth do not address enforcement at all.

One option the issue does not list deserves a mention and then a rejection: **a router macro** (`book_window_live "/books/:book_id/foo", BookFooLive`) in the LiveDashboard/Storybook shape, which makes misplacement structurally impossible. It is the right answer for a library publishing routes into someone else's router. For three hand-written routes in this repo's own 67-line router it buys a guarantee at the price of hiding the routes behind a macro, and this repo already values a readable router (the block carries an explanatory comment at `router.ex:33`). Not worth it below, say, a dozen routes.

## Recommendation

**Move the attachment into the views, and add the drift test. Do both, or neither is worth doing.**

Concretely, in one PR:

1. **Delete `on_mount:` from the router's `live_session`** and add one line to each of the three views, directly under `use LocalCentsWeb, :live_view`:

   ```elixir
   use LocalCentsWeb, :live_view

   on_mount LocalCentsWeb.BookWindow
   ```

   Keep the `live_session :book_window` block itself — it preserves today's soft-navigation grouping exactly, and its comment becomes a pointer rather than a contract restatement.

   Use the plain `Phoenix.LiveView.on_mount/1` macro, **not** a `use LocalCentsWeb.BookWindow` wrapper. Plausible's `__using__` exists because it composes into an app-wide `live_view/0` where the caller never types the hook name (`lib/plausible_web.ex:12`); here the hook is per-view, the macro would expand to exactly the line it replaces, and Livebook — the closest structural analogue in the survey — writes the bare call on all eight of its sidebar views. A macro that hides one line is a layer this repo does not need.

2. **Put the contract in the signature.** This is the highest-value, lowest-cost item, taken from Livebook's `AppLive` (3.4) and Firezone's hook chain (3.5). Change each view's mount head from `socket` to a pattern:

   ```elixir
   @impl Phoenix.LiveView
   def mount(_params, _session, %{assigns: %{book: %Book{id: book_id}}} = socket) do
   ```

   It costs no extra lines — it replaces the `socket.assigns.book.id` binding on the next line — and it converts a missing hook from a `KeyError` in an unrelated frame into a `FunctionClauseError` naming `mount/3`. More to the maintainer's actual complaint: the contract is now *in the code*, in the place a reader already looks, instead of in a comment beside it.

   Small mechanical note: `BookLive` and `BookCategoriesLive` do not currently alias `LocalCents.Tracking.Book` (only `BookReportLive` does), so this adds one `alias` line to two files.

3. **Delete all three duplicated comment blocks** (`book_live.ex:31`–`:33`, `book_categories_live.ex:28`–`:29`, `book_report_live.ex:46`–`:48`) and the two moduledoc paragraphs that restate the mount contract (`book_categories_live.ex:8`–`:11`, `book_report_live.ex:8`–`:10`). With steps 1 and 2 done they restate the signature, which `docs/comment-style.md` forbids. Replace each moduledoc paragraph with a single clause naming the hook — "its mount contract comes from `LocalCentsWeb.BookWindow`" — and let `BookWindow`'s moduledoc remain the one home for the *why*. That moduledoc is already good; it needs one edit, to say the hook is attached per-module rather than "via the `:book_window` `live_session`" (`book_window.ex:4`–`:5`).

4. **Add `test/local_cents_web/book_window_attachment_test.exs`**, in the shape of `test/local_cents/module_boundaries_doc_test.exs` — this repo's own precedent for turning a duplicated fact into a red build. Enumerate the routes from the router rather than hard-coding a module list, so a *new* view is covered automatically:

   ```elixir
   views =
     for route <- LocalCentsWeb.Router.__routes__(),
         String.starts_with?(route.path, "/books/:book_id"),
         {view, _action, _opts, _live_session} <- [route.metadata.phoenix_live_view],
         do: view

   assert views != [], "no /books/:book_id LiveView routes found — did the path change?"

   for view <- views do
     hook_ids = Enum.map(view.__live__().lifecycle.mount, & &1.id)

     assert {LocalCentsWeb.BookWindow, :default} in hook_ids, """
     #{inspect(view)} is routed under /books/:book_id but does not attach the
     LocalCentsWeb.BookWindow on_mount hook, so it will never register a viewer
     and its Book's runtime can reap under an open window. Add
     `on_mount LocalCentsWeb.BookWindow` under the `use` line.
     """
   end
   ```

   That comprehension was run against this repo and returns `[BookLive, BookCategoriesLive, BookReportLive]` today, with each view's `__live__().lifecycle.mount` currently empty — which is the point: it fails until step 1 lands, then guards it.

   Note this reads `view.__live__()` — the module's own baked-in hook list — rather than `route.metadata.phoenix_live_view`'s `live_session.extra.on_mount`, which is what the router-attached exemplars (Ash Authentication Phoenix) must read. Both are `@doc false` internals, but `__live__/0`'s contents are documented in `Phoenix.LiveView.__live__/1`'s `@doc` (`deps/phoenix_live_view/lib/phoenix_live_view.ex:469`–`:489`), including the `:on_mount` key, and it is how the framework itself loads the lifecycle on both render paths (`channel.ex:1159`, `static.ex:303`). It is the more stable of the two. Add a comment saying so, so the next reader knows the choice was deliberate.

   The route enumeration must also assert it found something — the boundary test's `assert MapSet.size(documented) > 0` guard (`test/local_cents/module_boundaries_doc_test.exs:24`) exists for exactly the failure where a format change makes the test vacuously pass.

**What not to do.** Skip the accessor. `BookWindow.book(socket)` would be a rename with a function call attached; the one good exemplar in the survey (Sequin's `current_user/1`) earns its keep because it resolves impersonation, and `@book` has nothing to resolve. If a future need appears — a derived "is this Book read-only?" say — add it then. Likewise skip the router macro (see the Weighing section) and skip a `use` wrapper.

**Where the decision lives.** No new ADR. This is the implementation of a decision ADR 0017 already made and already anticipated — its "Carried forward" bullet named "a candidate for a small `on_mount` hook if the view count grows" (`docs/adr/0017-in-window-secondary-views.md:53`–`:56`). Amend that bullet in place to record what shipped: the hook exists, it attaches per-module, and a router-driven test keeps that true. This repo has the precedent — ADR 0007's implementation note was updated in PR #174 rather than superseded. Add one sentence to `docs/book-runtime-lifecycle.md:14`–`:15`, which already names the hook as the uniform wiring, so a reader learns where the wiring lives. `CODING_STANDARDS.md` does not need an entry; one hook is not a convention.

**Honest residuals.**

- Moving attachment trades "a view can land in the wrong `live_session`" for "a view can omit a line." That is a better trade — the omission is visible in the file you are writing, rather than absent from a file you are not — but it is a trade, and step 4 is what actually closes it. Adopting step 1 without step 4 leaves the enforcement gap the issue calls the strongest argument.
- Both candidate test surfaces are undocumented LiveView internals. A LiveView upgrade could break the test. That is a loud, cheap failure, but it should be a known cost rather than a surprise.
- I did not verify that removing `on_mount:` from the `live_session` leaves the Storybook routes and dead render untouched by anything other than the additive merge described in 2.1. The merge is unconditional and hook lists are per-route, so there is no mechanism for interference, but it was reasoned from source rather than executed.
- Two of the issue's four directions were evaluated against a survey that found **no project anywhere** defining a type or struct for "the assigns a hook guarantees," and **no project anywhere** checking `live_session` membership at compile time. If either is what the maintainer actually wants, it would be novel work with no prior art to borrow — worth knowing before starting, not a reason against it.
