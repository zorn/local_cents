# Subscribing vs. Registering a Viewer: One Function or Two?

> Research note feeding the Book-runtime auto-shutdown work (see
> [ADR 0007](0007-book-runtime-and-persistence.html) and
> [Book Runtime Lifecycle](book-runtime-lifecycle.html)). LocalCents exposes two public
> functions where a document window needs both — `Tracking.subscribe/1` (passive PubSub
> listening) and `Tracking.register_viewer/1` (Presence tracking, which keeps the
> `BookServer` resident). Every document-window view calls both, back to back, in one
> place, which raises the fair question of whether the split is earning its keep. This
> note asks how real Elixir projects shape that API and recommends what LocalCents should
> do.
>
> Primary sources: the vendored [`Phoenix.PubSub`](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html),
> [`Phoenix.Presence`](https://phoenix.hexdocs.pm/Phoenix.Presence.html) and
> [`Phoenix.Tracker`](https://hexdocs.pm/phoenix_pubsub/Phoenix.Tracker.html) source and
> docs (`phoenix` 1.8.9, `phoenix_pubsub` 2.2.0, `phoenix_live_view` 1.2.7), the official
> Phoenix [Presence guide](https://phoenix.hexdocs.pm/presence.html), Phoenix's own
> context generator templates, and the source of roughly thirty open-source
> Elixir/Phoenix projects read on GitHub at pinned commits — chiefly
> [Livebook](https://github.com/livebook-dev/livebook), the closest structural analogue to
> LocalCents. Project claims cite repo files by `path:line`; external code by permalink.
> Elixir Forum threads appear in a clearly-marked secondary section, with every factual
> claim traced back to the primary source that owns it.
>
> **Status:** research complete, no code changed. The recommendation is to **keep the two
> functions**, with two small optional refinements to the docs.

## The question, precisely

LocalCents has two entry points on the `LocalCents.Tracking` facade:

```elixir
# lib/local_cents/tracking.ex:557
@spec subscribe(Book.id()) :: :ok | {:error, term()}
def subscribe(id) when is_binary(id), do: BookServer.subscribe(id)

# lib/local_cents/tracking.ex:576
@spec register_viewer(Book.id()) :: {:ok, ref :: binary()} | {:error, term()}
def register_viewer(id) when is_binary(id), do: BookServer.register_viewer(id)
```

`subscribe/1` bottoms out in `Phoenix.PubSub.subscribe/3` on `"book:<id>"`
(`lib/local_cents/tracking/book_server.ex:296`); `register_viewer/1` bottoms out in
`Presence.track/4` on `"book_presence:<id>"`
(`lib/local_cents/tracking/book_server.ex:315`). Only the second counts toward keeping a
`BookServer` resident.

The document-window `on_mount` hook is the one place that wants both, and it calls them
on adjacent lines (`lib/local_cents_web/book_window.ex:41`):

```elixir
if connected?(socket) do
  Tracking.subscribe(book_id)
  register_viewer(book_id)
end
```

## 1. Phoenix models these as two verbs and gives you no way to truly merge them

The first piece of evidence is structural, not stylistic. **`Phoenix.PubSub.subscribe/3`
has no pid-taking arity.** Its doc line is "Subscribes the caller to the PubSub adapter's
topic," its spec is `subscribe(t, topic, keyword) :: :ok | {:error, term}`, and its body
is `Registry.register(pubsub, topic, opts[:metadata])`, which registers `self()`
(`deps/phoenix_pubsub/lib/phoenix/pubsub.ex:179`). No arity accepts another process.
`unsubscribe/2` is the same ("Unsubscribes the caller",
`deps/phoenix_pubsub/lib/phoenix/pubsub.ex:211`), as are the subscribe wrappers
[`Phoenix.Endpoint`](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html) generates
(`deps/phoenix/lib/phoenix/endpoint.ex:362`).

`Phoenix.Presence` is deliberately the opposite. Its callback is
`@callback track(pid, topic, key, meta)`, documented as "Track an arbitrary process as a
presence" (`deps/phoenix/lib/phoenix/presence.ex:239`). Tracking someone else is a
first-class supported concept; subscribing someone else is not expressible.

That asymmetry settles the "who owns the subscription" question outright. A combined
`join(book_id)` could only ever subscribe *its own caller*, because that is the only
process `Phoenix.PubSub` will let it subscribe. Merging is therefore never a way to move
ownership of the subscription — only a way to hide one of two side effects behind a name
that advertises one. Every "combined" function in the survey below is a caller-side
convenience wrapper, nothing more.

A context function subscribing its caller as a side effect is, meanwhile, entirely
ordinary — it is what Phoenix's own generators emit. `mix phx.gen.context --scope` writes
a `subscribe_<plural>(scope)` into the generated context whose whole body is a
`Phoenix.PubSub.subscribe/3`, and whose `@doc` does not even mention that a process is
being registered
([schema_access_scope.ex.eex#L15-L19](https://github.com/phoenixframework/phoenix/blob/bee0f32e7326fe82ec6b4858a7e1f87de39dbaed/priv/templates/phx.gen.context/schema_access_scope.ex.eex#L15-L19)).
The implicit caller is so assumed it goes undocumented. Nothing in `Phoenix.PubSub`,
`Phoenix.Presence`, `Phoenix.Tracker`, or the Phoenix guides warns against the practice.
So LocalCents' `subscribe/1` is idiomatic as written; the open question is only whether
`register_viewer/1` should ride along inside it.

Second structural fact: **`Phoenix.Presence` exposes no `subscribe` at all.** The
generated API is `track/3,4`, `untrack/2,3`, `update/3,4`, `list/1`, `get_by_key/2`
(`deps/phoenix/lib/phoenix/presence.ex:391`), and `mix phx.gen.presence` emits a
three-line `use Phoenix.Presence` module with no subscribe helper
(`deps/phoenix/priv/templates/phx.gen.presence/presence.ex.eex`). Phoenix ships no
first-party primitive that does both, and no first-party guidance for or against building
one.

### The official guide's canonical example is two named functions

Phoenix's own [Presence guide](https://phoenix.hexdocs.pm/presence.html), under "Usage
With LiveView," defines exactly the pair LocalCents has — two named wrappers on the
Presence module:

```elixir
def track_user(name, params), do: track(self(), "online_users", name, params)

def subscribe(), do: Phoenix.PubSub.subscribe(Hello.PubSub, "proxy:online_users")
```

and calls them on adjacent lines inside `if connected?(socket)`:

```elixir
if connected?(socket) do
  HelloWeb.Presence.track_user(params["name"], %{id: params["name"]})
  HelloWeb.Presence.subscribe()
  stream(socket, :presences, HelloWeb.Presence.list_online_users())
else
   socket
end
```

Three separate calls — track, subscribe, load initial state — composed by the caller. The
guide never merges them and never suggests merging them. Note the zero arity on
`subscribe/0`: it is the tell that the function can only serve its caller.

The channel flavor in the `Phoenix.Presence` moduledoc keeps them separate too, just less
visibly. A channel process is already subscribed to its own topic by the channel server
(`deps/phoenix/lib/phoenix/channel/server.ex:444`), and tracking is still a *later,
separate* step deferred to `handle_info(:after_join, ...)`
(`deps/phoenix/lib/phoenix/presence.ex:56`). Even where subscription is free, Phoenix does
not fold tracking into it.

## 2. Livebook — the closest structural analogue — splits them, and the split is load-bearing

Livebook is the nearest match to LocalCents: a per-document GenServer, many viewers, and a
session that shuts itself down when its clients leave. It keeps the two concerns fully
apart, and notably uses no Presence at all.

[`Livebook.Session.subscribe/1`](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L280-L295)
is a bare PubSub call taking the session **id**, with no side effects and no state return:

```elixir
@spec subscribe(id()) :: :ok | {:error, term()}
def subscribe(session_id) do
  Phoenix.PubSub.subscribe(Livebook.PubSub, "sessions:#{session_id}")
end
```

[`Livebook.Session.register_client/3`](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L229-L244)
is a `GenServer.call` taking the session **pid**, and it explicitly does *not* subscribe
you — the docstring hands that back to the caller:

> Registers a session client, so that the session is aware of it.
>
> The client process is automatically unregistered when it terminates.
>
> Returns the current session data, which the client can then keep in sync with the
> session server by subscribing to the `sessions:id` topic and receiving operations to
> apply.

`SessionLive.mount/3` calls both, in that order, gated on `connected?/1`
([session_live.ex#L20-L32](https://github.com/livebook-dev/livebook/blob/main/lib/livebook_web/live/session_live.ex#L20-L32)).

**The split is genuinely load-bearing there, for the same reason it is here.**
`LivebookWeb.SessionLive.AppTeamsLive`, a nested child LiveView, calls `Session.subscribe/1`
**without** `register_client/3`
([app_teams_live.ex#L28-L32](https://github.com/livebook-dev/livebook/blob/main/lib/livebook_web/live/session_live/app_teams_live.ex#L28-L32))
— it needs the operation stream but must not count as another client, since the parent
already registered the browser tab. Livebook's home and open pages take a third path
entirely: a coarse, list-level
[`Livebook.Sessions.subscribe/0`](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/sessions.ex#L78-L91)
on a `"tracker_sessions"` topic that carries no keep-alive semantics — structurally the
same move as LocalCents' library window subscribing to every Book without viewing any.

Two design choices worth naming:

- **Livebook's registration returns state.** `register_client/3` replies with
  `{Data.t(), client_id}`, so mount is one round trip: register, get the snapshot, then
  subscribe. LocalCents instead does `open_book/1` → `get_book/1` → `subscribe/1` →
  `register_viewer/1` (`lib/local_cents_web/book_window.ex:38-44`) — one more hop, but
  `register_viewer/1` stays a pure lifecycle concern.
- **Livebook uses monitors, not Presence**, and auto-shutdown is opt-in per session
  (`auto_shutdown_ms` is `nil` for ordinary notebooks and set only for deployed apps).
  See section 5.

## 3. Field survey: what seventeen projects actually do

The table below covers every project read that has both a broadcast channel and a
participation concept, at pinned commits. Six further repositories were read and turned
out to have no participation tracking at all. The shapes divide three ways.

| Project | Shape | Evidence |
|---|---|---|
| [Livebook](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L229-L295) | **Two named** — `subscribe/1` + `register_client/3` | see section 2 |
| Phoenix's Presence guide | **Two named** — `subscribe/0` + `track_user/2` | [presence.html](https://phoenix.hexdocs.pm/presence.html) |
| [Firezone](https://github.com/firezone/firezone/blob/fe2b22786e3c4e1ec8fd67075568013b996077c4/elixir/lib/portal/presence.ex#L52) | **Two named**, per topic module — `track/3` + `subscribe/1` | [`track` #L52](https://github.com/firezone/firezone/blob/fe2b22786e3c4e1ec8fd67075568013b996077c4/elixir/lib/portal/presence.ex#L52), [`subscribe` #L65](https://github.com/firezone/firezone/blob/fe2b22786e3c4e1ec8fd67075568013b996077c4/elixir/lib/portal/presence.ex#L65) |
| [live-slides](https://github.com/matt-savvy/live-slides/blob/52c55d6f9aef94e3f913822b37116ef8253e8127/lib/live_slides/presentations.ex#L211-L213) | **Two named** — `subscribe/1` + `track/2` + `tracked_count/1` | [#L211](https://github.com/matt-savvy/live-slides/blob/52c55d6f9aef94e3f913822b37116ef8253e8127/lib/live_slides/presentations.ex#L211-L213), [#L225](https://github.com/matt-savvy/live-slides/blob/52c55d6f9aef94e3f913822b37116ef8253e8127/lib/live_slides/presentations.ex#L225-L227) |
| [cuberacer_live](https://github.com/gcpreston/cuberacer_live/blob/3a4b120bf2ca7589c4d915f71a88c0ee13c4edd7/lib/cuberacer_live/room.ex#L25-L33) | **Two named**, composed by a private web-layer helper | [room.ex#L25](https://github.com/gcpreston/cuberacer_live/blob/3a4b120bf2ca7589c4d915f71a88c0ee13c4edd7/lib/cuberacer_live/room.ex#L25-L33), [room_live.ex#L57](https://github.com/gcpreston/cuberacer_live/blob/3a4b120bf2ca7589c4d915f71a88c0ee13c4edd7/lib/cuberacer_live_web/live/room/room_live.ex#L57-L62) |
| [Supabase Realtime](https://github.com/supabase/realtime/blob/6cf6446473a29897b82672f82ace356a6f483507/lib/realtime_web/channels/realtime_channel/presence_handler.ex#L141) | **Two**, decoupled in time — channel `join` subscribes, a later `"track"` wire event opts in | [presence_handler.ex#L141](https://github.com/supabase/realtime/blob/6cf6446473a29897b82672f82ace356a6f483507/lib/realtime_web/channels/realtime_channel/presence_handler.ex#L141) |
| [MBTA dotcom](https://github.com/mbta/dotcom/blob/e072f4869f971d508fc3a9827aac50bc8ceee4cc/lib/dotcom/predictions/manager.ex#L25-L36) | **One** — `subscribe/1` does subscribe + track + demand-start | [manager.ex#L25](https://github.com/mbta/dotcom/blob/e072f4869f971d508fc3a9827aac50bc8ceee4cc/lib/dotcom/predictions/manager.ex#L25-L36) |
| [Level 10](https://github.com/dnsbty/level10/blob/92e85d0a0606a04513242c614fe9770a3da6ecd2/lib/level10/games.ex#L770-L781) | **One** — `subscribe/2` also tracks the player | [games.ex#L770](https://github.com/dnsbty/level10/blob/92e85d0a0606a04513242c614fe9770a3da6ecd2/lib/level10/games.ex#L770-L781) |
| [Teiserver](https://github.com/beyond-all-reason/teiserver/blob/3e364b46c9fc310f79654aeacb0b55fa6634b051/lib/teiserver/tachyon_lobby/lobby.ex#L99) | **One** — `join/3` registers + monitors + returns a snapshot | [lobby.ex#L99](https://github.com/beyond-all-reason/teiserver/blob/3e364b46c9fc310f79654aeacb0b55fa6634b051/lib/teiserver/tachyon_lobby/lobby.ex#L99) |
| [spectator_mode](https://github.com/gcpreston/spectator_mode/blob/a3c063409dbdbb234e1918f57562422647ab117a/lib/spectator_mode/streams.ex#L66-L80) | **Both** — combined `register_viewer/2` for data; separate `subscribe/0` + `track_viewer/2` for counting | [streams.ex#L66](https://github.com/gcpreston/spectator_mode/blob/a3c063409dbdbb234e1918f57562422647ab117a/lib/spectator_mode/streams.ex#L66-L80), [presence.ex#L16](https://github.com/gcpreston/spectator_mode/blob/a3c063409dbdbb234e1918f57562422647ab117a/lib/spectator_mode_web/channels/presence.ex#L16) |
| [lax](https://github.com/jtormey/lax/blob/main/lib/lax_web/presence.ex#L12-L22) | **One**, web layer — `track_online_users(socket)` | [presence.ex#L12](https://github.com/jtormey/lax/blob/main/lib/lax_web/presence.ex#L12-L22) |
| [oli-torus](https://github.com/Simon-Initiative/oli-torus/blob/master/lib/oli_web/live/collaboration_live/collab_space_view.ex#L72-L79) | **Inline**, no wrapper — subscribe then track in `mount/3` | `collab_space_view.ex:72`, `:74` |
| [littlechat](https://github.com/littlelines/littlechat/blob/master/lib/littlechat_web/live/room/show_live.ex#L83-L90) | **Inline** | `show_live.ex:83`, `:90` |
| [phxBB](https://github.com/APB9785/phxBB/blob/master/lib/phx_bb_web/live/forum_live.ex#L25-L40) | **Inline** | `forum_live.ex:25`, `:38` |
| [Papercups](https://github.com/papercups-io/papercups/blob/6a6f5adc7f0cef5813b2c2f1c0659922defaf976/lib/chat_api_web/channels/conversation_channel.ex#L45-L70) | **Inline**, raw `Presence.track` in `after_join` | [conversation_channel.ex#L45](https://github.com/papercups-io/papercups/blob/6a6f5adc7f0cef5813b2c2f1c0659922defaf976/lib/chat_api_web/channels/conversation_channel.ex#L45-L70) |
| [Codebattle](https://github.com/hexlet-codebattle/codebattle/blob/9a4dced9ed589d014ff0384fe9e7813fb7009d81/apps/codebattle/lib/codebattle_web/channels/main_channel.ex#L155-L167) | **Inline**, subscribe in `join/3`, track in `after_join` | [main_channel.ex#L155](https://github.com/hexlet-codebattle/codebattle/blob/9a4dced9ed589d014ff0384fe9e7813fb7009d81/apps/codebattle/lib/codebattle_web/channels/main_channel.ex#L155-L167) |
| [Mozilla Hubs](https://github.com/Hubs-Foundation/reticulum/blob/fc02d985e2a4b9cceac68d2389c736e991d6fdf2/lib/ret_web/channels/hub_channel.ex#L967-L972) | **Inline** | [hub_channel.ex#L967](https://github.com/Hubs-Foundation/reticulum/blob/fc02d985e2a4b9cceac68d2389c736e991d6fdf2/lib/ret_web/channels/hub_channel.ex#L967-L972) |

No participation tracking at all, verified by grepping each clone's `lib/` tree: Keila,
Plausible (its "current visitors" figure is a ClickHouse query), Oban Web,
`phoenix_live_dashboard`, Rauversion, and `elixir-desktop`. Mobilizon and the Cambiatus
backend could not be read — the former lives on framagit, the latter is no longer public.

**Tally.** Of the sixteen applications in the table (the Phoenix guide is framework
documentation, not an app): **six expose two named functions**, **five expose one combined
function**, and **six do it inline at the call site with no wrapper**. `spectator_mode`
appears in both the one- and two-function rows because it genuinely does one of each on
different modules, so the rows sum to seventeen.

Counting *operations* rather than *functions* makes the picture lopsided: fifteen of
sixteen treat subscribing and participating as two distinct steps somewhere in the stack.
Whether they get one name or two is a wrapper decision, and it is usually made in the web
layer.

**Nobody uses an option flag.** There is no `subscribe(id, track: true)` anywhere in the
survey. When projects want the pair to be optional, they overload on argument type (Level
10's `subscribe(socket, player_id)` clause silently degrades to track-only) or route it
through a separate wire event (Supabase Realtime).

### What actually predicts the choice

The one-vs-two split does not track taste. It tracks **whether any caller needs one
without the other**:

- **Two functions wins wherever the roles are asymmetric.** Firezone is the extreme case:
  no process ever tracks *and* subscribes the same topic. The tracked party announces
  itself (a client channel tracks, an admin LiveView subscribes), so a combined call would
  have no callers at all. `live-slides` is the same story inside one LiveView — the
  `:view` action calls `subscribe/1` **only** and reads `tracked_count/1`, while the
  `:live` action calls both on adjacent lines
  ([view.ex#L26](https://github.com/matt-savvy/live-slides/blob/52c55d6f9aef94e3f913822b37116ef8253e8127/lib/live_slides_web/live/presentation_live/view.ex#L26-L29)
  vs
  [#L50](https://github.com/matt-savvy/live-slides/blob/52c55d6f9aef94e3f913822b37116ef8253e8127/lib/live_slides_web/live/presentation_live/view.ex#L50-L54)).
  That is precisely LocalCents' library window versus its document window.
- **One function wins where tracking is genuinely an implementation detail of
  subscribing.** MBTA's `Presence.track` uses a *constant* key, `"predictions"`, so the
  metas list is nothing but a distributed refcount of subscribers
  ([manager.ex#L111](https://github.com/mbta/dotcom/blob/e072f4869f971d508fc3a9827aac50bc8ceee4cc/lib/dotcom/predictions/manager.ex#L111-L116)).
  There is no passive-subscriber role in that system, so there is nothing to separate, and
  naming the whole thing `subscribe/1` is honest.

LocalCents sits squarely in the first camp.

## 4. What the combined form looks like when it appears

Three real shapes, none of them an opts flag.

**A socket-shaped web-layer helper.** `LaxWeb.Presence.Live.track_online_users/1` takes
the socket, gates on `connected?/1`, tracks, subscribes, seeds assigns, and attaches a
`handle_info` hook, all in one call
([presence.ex#L12-L22](https://github.com/jtormey/lax/blob/main/lib/lax_web/presence.ex#L12-L22)).
What makes this safe is where it lives: the **web** layer, taking a socket and returning a
socket. It is a mount helper, not a context API. `cuberacer_live` does the same thing more
explicitly — it keeps two context functions and names the composition privately, in the
LiveView:

```elixir
defp track_and_subscribe(socket, user, session) do
  if connected?(socket) do
    Room.track_presence(self(), session, user)
    Room.subscribe(session)
  end
end
```
([room_live.ex#L57-L62](https://github.com/gcpreston/cuberacer_live/blob/3a4b120bf2ca7589c4d915f71a88c0ee13c4edd7/lib/cuberacer_live_web/live/room/room_live.ex#L57-L62))

That is LocalCents' `BookWindow` `on_mount` hook, function for function.

**A `join/3` that registers and returns a snapshot.** Teiserver's lobby takes the
participant pid, monitors it, and replies with the current state
([lobby.ex#L99](https://github.com/beyond-all-reason/teiserver/blob/3e364b46c9fc310f79654aeacb0b55fa6634b051/lib/teiserver/tachyon_lobby/lobby.ex#L99),
reply at
[#L490](https://github.com/beyond-all-reason/teiserver/blob/3e364b46c9fc310f79654aeacb0b55fa6634b051/lib/teiserver/tachyon_lobby/lobby.ex#L490)).
There is no PubSub for members at all — the lobby `send`s directly to the pids it holds —
so "join" combines registration with *delivery*, not with subscription. Teiserver still
keeps a separate `subscribe_updates/0` for the passive lobby-list watchers
([tachyon_lobby.ex#L26-L29](https://github.com/beyond-all-reason/teiserver/blob/3e364b46c9fc310f79654aeacb0b55fa6634b051/lib/teiserver/tachyon_lobby.ex#L26-L29)),
which is the same passive/active split under different names.

**A context `subscribe/2` that also tracks.** `Level10.Games.subscribe/2` is the
cautionary one
([games.ex#L770-L781](https://github.com/dnsbty/level10/blob/92e85d0a0606a04513242c614fe9770a3da6ecd2/lib/level10/games.ex#L770-L781)):

```elixir
def subscribe(game_code, player_id) when is_binary(game_code) do
  topic = "game:" <> game_code

  with :ok <- Phoenix.PubSub.subscribe(Level10.PubSub, topic),
       {:ok, _} <- Presence.track_player(game_code, player_id) do
    :ok
  end
end

def subscribe(socket, player_id) do
  with {:ok, _} <- Presence.track_player(socket, player_id), do: :ok
end
```

The merge did not remove a concept; it hid one. A function named `subscribe` now carries a
participation side effect, its two clauses do *different* things (the socket clause tracks
but never subscribes), the caller cannot ask for one without the other, and the `@doc`
describes only the subscription — "Subscribe a process to updates for the specified game"
— so the presence half is undocumented. This is the exact failure mode a merged
`Tracking.subscribe/1` would invite here.

Two counter-examples show how to merge *well*, if one ever wants to. Firezone built a
combining wrapper `Clients.connect/3` **over** its granular primitives — and that wrapper
composes two `track` calls and never absorbs `subscribe`
([presence.ex#L12-L17](https://github.com/firezone/firezone/blob/fe2b22786e3c4e1ec8fd67075568013b996077c4/elixir/lib/portal/presence.ex#L12-L17)).
And when Phoenix itself merged two side effects, it named the function after both:
`Phoenix.ChannelTest.subscribe_and_join/4`
([channel_test.ex#L378-L396](https://github.com/phoenixframework/phoenix/blob/bee0f32e7326fe82ec6b4858a7e1f87de39dbaed/lib/phoenix/test/channel_test.ex#L378-L396)).
The rule that falls out of the survey: keep the primitives, and if you add a wrapper, let
its name confess everything it does.

## 5. Lifecycle from participants: presence, monitors, or subscriber counts

Four mechanisms appear, and the choice is independent of the one-or-two API question.

**Presence diff plus a grace timer** — LocalCents' mechanism — is also `cuberacer_live`'s.
Join and leave events adjust the participant map, and hitting zero arms an empty-room timer
rather than stopping immediately
([room_server.ex#L116-L147](https://github.com/gcpreston/cuberacer_live/blob/3a4b120bf2ca7589c4d915f71a88c0ee13c4edd7/lib/cuberacer_live/game/room_server.ex#L116-L121));
only the timer stops the server, under `use GenServer, restart: :transient`
([#L190](https://github.com/gcpreston/cuberacer_live/blob/3a4b120bf2ca7589c4d915f71a88c0ee13c4edd7/lib/cuberacer_live/game/room_server.ex#L190-L193)).
That is `reconcile_viewers/1` and `arm_reap/1` by another name
(`lib/local_cents/tracking/book_server.ex:486`, `:494`), down to the `:transient` restart
strategy. Two other projects converge on the same skeleton — `sagents`' `AgentServer`
subscribes to its own presence topic and arms `:shutdown_no_viewers` on an empty diff
([agent_server.ex#L2841](https://github.com/sagents-ai/sagents/blob/dd86d3dd9b02f9275da4d38a37c025f37f26c59b/lib/sagents/agent_server.ex#L2841-L2867)),
and `lasso-rpc`'s `EventStream` does belt *and* braces: cancel the timer on rejoin **and**
re-check at fire time
([event_stream.ex#L448](https://github.com/jaxernst/lasso-rpc/blob/c4369bc9126bf08f08ac1ef9a3577cb67394cb5e/lib/lasso_web/dashboard/event_stream.ex#L448-L473)),
which is what `handle_info(:reap, ...)` does here.

Across ten idle-shutdown implementations read, **none** used the built-in
`{:ok, state, timeout}` / `handle_info(:timeout, ...)` form; all used an explicit
`Process.send_after`, because the GenServer timeout is reset by any unrelated message.
Grace periods ranged from none (Wocky, which would reap on any LiveView reconnect) through
30 seconds (cuberacer, Hyper, lasso-rpc) to roughly eleven minutes (Supabase Realtime).
LocalCents' 60-second default sits mid-range, and the grace period is load-bearing rather
than cosmetic: LiveView's own docs note that a dropped connection means "the client
gracefully reconnects to the server, calling `mount/3` and `handle_params/3` again"
([phoenix_live_view.ex#L42-L44](https://github.com/phoenixframework/phoenix_live_view/blob/b97790b10fdb99ffaa1c993d779dfd3e95a503f9/lib/phoenix_live_view.ex#L42-L44))
— a **new pid**, so any presence- or monitor-based scheme without a debounce reaps on
every network blip and page refresh.

**Presence polling** is MBTA's: a 5-second poll of `Presence.list/1`, and zero subscribers
means `{:stop, :normal, state}`
([manager.ex#L73-L81](https://github.com/mbta/dotcom/blob/e072f4869f971d508fc3a9827aac50bc8ceee4cc/lib/dotcom/predictions/manager.ex#L73-L81)).
Their comment on the restart strategy is worth reading before anyone changes ours:

> `restart: :transient` is necessary here because when the subscriber count drops to 0, we
> want the GenServer to gracefully shutdown. With the default value of `:permanent`, it
> would shut down but then try to start back up again, detect that it has no subscribers,
> shut down again, start back up again, and so on.
> ([manager.ex#L13-L18](https://github.com/mbta/dotcom/blob/e072f4869f971d508fc3a9827aac50bc8ceee4cc/lib/dotcom/predictions/manager.ex#L13-L18))

**Monitors** are Livebook's and Teiserver's. `register_client/3` calls
`Process.monitor(client_pid)` inside the session
([session.ex#L1109-L1122](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L1109-L1122)),
a catch-all `{:DOWN, ...}` clause turns the exit into a `{:client_leave, client_id}`
operation
([#L1714](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L1714-L1723)),
and `schedule_auto_shutdown/1` arms or cancels a timer off `map_size(clients_map)`
([#L1069](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L1069-L1095))
— the same grace-with-cancel shape LocalCents has, from a different source of truth.
Teiserver's lobby stops on `{:shutdown, :empty}` when its DOWN handler empties both member
lists
([lobby.ex#L1167](https://github.com/beyond-all-reason/teiserver/blob/3e364b46c9fc310f79654aeacb0b55fa6634b051/lib/teiserver/tachyon_lobby/lobby.ex#L1167-L1170)).

The monitor approach costs one thing LocalCents gets for free: a monitor held *inside* the
document process dies with it. LocalCents' `Presence` is a peer process, so a
crash-restarted `BookServer` reads `Presence.list/1` at `init` and does not reap out from
under a still-open window (see the crash-resilience section of
[Book Runtime Lifecycle](book-runtime-lifecycle.html)). That is a real advantage of the
Presence choice, not a rationalization.

**A separate participant counter** is Supabase Realtime's, and it is the most defensive
design found. It refuses to use Presence for lifecycle at all — Presence there is a
user-facing feature — and keeps a distinct `Realtime.UsersCounter` registered with the
transport pid at channel join
([realtime_channel.ex#L179](https://github.com/supabase/realtime/blob/6cf6446473a29897b82672f82ace356a6f483507/lib/realtime_web/channels/realtime_channel.ex#L179)).
The tenant runtime samples that count into an eleven-slot ring buffer at 60-second
intervals and shuts down only after eleven consecutive zero readings
([connect.ex#L32](https://github.com/supabase/realtime/blob/6cf6446473a29897b82672f82ace356a6f483507/lib/realtime/tenants/connect.ex#L32)).
Their split of "presence, the feature" from "participation, the lifecycle signal" is
exactly what LocalCents' `subscribe/1` vs. `register_viewer/1` encodes.

**Subscriber counts** — counting the PubSub registry itself, e.g. `Registry.count/1` or `Registry.count_match/3` —
appear in exactly **one** project out of the whole survey. Because
`Phoenix.PubSub.subscribe/3` is `Registry.register/3`, the PubSub name *is* a Registry and
can be counted; `webtorrent_tracker` does this deliberately, using
`Registry.count_match/3` and `Registry.select/2` against the PubSub server and leaning on
`subscribe(..., metadata: ...)` so the entries are matchable
([user_socket.ex#L93-L112](https://github.com/woohp/webtorrent_tracker/blob/18c163b1c28f806cf18a2b25c30cdb031737dd44/lib/webtorrent_tracker_web/user_socket.ex#L93-L112)).
It works, but it reaches into an undocumented implementation detail, and — decisively for
us — it cannot tell a passive listener from a participant. `Phoenix.Tracker` offers no
count either; its API is `track/untrack/update/list/get_by_key/graceful_permdown`
(`deps/phoenix_pubsub/lib/phoenix/tracker.ex`), and its shutdown documentation is about
*replica* shutdown, a different concern.

LocalCents' reason for rejecting subscriber counts is the reason almost
nobody can use them: the library window subscribes to every Book without viewing any
(`lib/local_cents_web/live/library_live.ex:66`, `:366`, `:392`), so a subscriber count
would pin every Book resident forever. Livebook hit the identical wall and resolved it the
identical way — a coarse separate topic for passive watchers
([sessions.ex#L78-L91](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/sessions.ex#L78-L91))
plus an explicit registration for participants. Two independent projects reaching the same
split under the same constraint is the strongest single piece of evidence in this note.

One caveat the first-party docs raise about Presence-driven lifecycle: `Phoenix.Tracker`'s
"Application Shutdown" section warns that after a `SIGTERM` or a crash, "other nodes will
still have to wait the `:down_period` to notice that the tracker's presences are gone"
(`deps/phoenix_pubsub/lib/phoenix/tracker.ex:74-95`). That is a *distributed* concern.
LocalCents runs single-node on the desktop, where a dead viewer's leave is local and
prompt, so it does not bite today — but it is worth remembering if a web deployment ever
clusters.

## 6. Naming

`register_viewer` is not an idiosyncratic coinage: `spectator_mode` independently uses
`register_viewer/2` for the same concept
([streams.ex#L66](https://github.com/gcpreston/spectator_mode/blob/a3c063409dbdbb234e1918f57562422647ab117a/lib/spectator_mode/streams.ex#L66-L80)),
and Livebook uses `register_client/3` in the same slot. The `register_*` verb reads better
than the alternatives the survey turned up: `track` names the mechanism rather than the
intent, `join` implies a symmetric explicit leave (LocalCents has none — the registration
dies with the process), and `connect` is already taken in most apps for something else
(Firezone uses it to compose several `track` calls; Level 10 uses it for an existence
check).

No change recommended.

## Community signal (secondary sources)

Practitioner threads, not authorities. Each claim is anchored to the primary source that
owns it.

- ["How to properly monitor when a LiveView socket disconnects?"](https://elixirforum.com/t/how-to-properly-monitor-when-a-liveview-socket-disconnects/62566)
  — the recommended shape is that "the genserver itself should just monitor the socket,
  and then it can terminate itself when the socket goes away," which is Livebook's and
  Teiserver's implementation
  ([session.ex#L1109](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L1109-L1122)).
  A second reply argues against relying on any disconnect callback and in favor of periodic
  revalidation — a useful reminder that a leave signal is a hint, which is the same caution
  `Phoenix.Tracker`'s shutdown docs give (`deps/phoenix_pubsub/lib/phoenix/tracker.ex:74`),
  and which Supabase Realtime's eleven-sample buffer takes to its logical conclusion. The
  thread never proposes merging subscription into registration; they are treated as
  unrelated problems.
- ["Is there a way to self terminate a GenServer after no activity?"](https://elixirforum.com/t/is-there-a-way-to-self-terminate-a-genserver-after-no-activity/2889)
  — confirms the idiom LocalCents, Livebook, and cuberacer_live all use: an explicit
  `Process.send_after` timer cancelled on renewed activity, rather than the GenServer
  `:timeout` return value, which any incoming message resets. LocalCents arms and cancels
  explicitly (`lib/local_cents/tracking/book_server.ex:486`), which is the right call since
  a `BookServer` receives commands constantly while idle of *viewers*.

## Recommendation for LocalCents

**Keep the two functions.** The survey does not show a dominant idiom in the abstract —
six projects name two functions, five name one, five wrap nothing at all — but it shows a
very clear rule for *which* to pick, and LocalCents lands unambiguously on the two-function
side of it.

1. **The split is load-bearing here, in both directions, today.**
   `LocalCentsWeb.LibraryLive` subscribes to every Book without viewing any
   (`lib/local_cents_web/live/library_live.ex:66`, `:366`, `:392`); merge the functions and
   the library pins every Book resident forever, defeating the whole point of ADR 0007's
   lifecycle. The reverse is exercised too: the shutdown suite's `start_viewer/1` helper
   calls `register_viewer/1` **alone**, with no subscription, to drive lifecycle
   transitions without a LiveView
   (`test/local_cents/tracking/book_server_shutdown_test.exs:150`), and seven Tracking and
   BookServer tests call `subscribe/1` alone to assert broadcasts (e.g.
   `test/local_cents/tracking_test.exs:264`,
   `test/local_cents/tracking/book_server_test.exs:13`). Both halves have real solo callers.
2. **That is exactly the condition the survey says predicts two functions.** Firezone and
   `live-slides` split for the same reason — an observer role that must never count as a
   participant. The projects that merged (MBTA, Level 10) have no passive-subscriber role
   at all; MBTA's presence key is a literal constant because tracking there *is* subscriber
   counting.
3. **The closest structural analogue reached the same design independently.** Livebook
   splits `subscribe/1` from `register_client/3`, has a nested view that subscribes without
   registering, and routes passive list watchers to a separate coarse topic.
4. **Merging cannot buy the thing a merge usually buys.** `Phoenix.PubSub.subscribe/3` has
   no pid arity (`deps/phoenix_pubsub/lib/phoenix/pubsub.ex:179`) while `Presence.track/4`
   does (`deps/phoenix/lib/phoenix/presence.ex:239`), so a combined function could never
   own the subscription on a caller's behalf — only hide a second side effect behind a
   one-verb name. Level 10 shows the result: an undocumented participation side effect on
   a function called `subscribe`.
5. **Phoenix's own guide ships this exact pair**, two named wrappers called on adjacent
   lines under `connected?/1`, which makes the split the low-surprise reading for anyone
   new to the codebase.

The maintainer's observation — that only one caller wants both, and always calls them
together — is correct, and it is already solved at the right layer. The merge exists: it is
the `LocalCentsWeb.BookWindow` `on_mount` hook (`lib/local_cents_web/book_window.ex:34`),
a web-layer mount helper, precisely where `lax` puts `track_online_users/1` and
`cuberacer_live` puts its private `track_and_subscribe/3`. The context keeps two honest
verbs; the window layer composes them once, in one place, so no view can drift. That is the
shape the survey endorses and LocalCents already has it.

If a future change does want one call at the context boundary, the survey gives a clear
rule: **keep both primitives and add a wrapper whose name confesses both effects** — the
way Firezone layered `connect/3` over its `track` calls without absorbing `subscribe`, and
the way Phoenix named `subscribe_and_join/4`. What the survey does not support is
overloading `subscribe/1` to also register a viewer.

Two optional refinements, neither of which changes the API:

- **Consider having `register_viewer/1` return the Book's current state**, the way
  Livebook's `register_client/3` returns `{Data.t(), client_id}`
  ([session.ex#L229](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex#L229-L244))
  and Teiserver's `join/3` returns a lobby snapshot. It would collapse a mount round trip
  and close the small window between `get_book/1` and `register_viewer/1`. Weigh it against
  keeping `register_viewer/1` a pure lifecycle concern; the current separation is
  defensible and this is not urgent.
- **Note the duplicate-subscription rule in `subscribe/1`'s doc.** `Phoenix.PubSub` states
  that "Callers should only subscribe to a given topic a single time," that duplicates
  silently double the messages delivered, and that a single `unsubscribe/2` drops all of
  them (`deps/phoenix_pubsub/lib/phoenix/pubsub.ex:186`). Since the library window
  subscribes per Book from three places (`lib/local_cents_web/live/library_live.ex:66`,
  `:366`, `:392`), that rule belongs where a future caller will read it.
