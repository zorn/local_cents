# Sync Architectures for the Offline Demo — the Option Space

> Research note feeding [issue #222](https://github.com/zorn/local_cents/issues/222) under offline-demo map [#210](https://github.com/zorn/local_cents/issues/210) — "what are the concrete, viable ways to run the Mac app (Tauri-embedded Phoenix/BEAM) and a browser as two genuinely separate Automerge instances that each own a document and sync when back online?"
>
> This note **lays out the options, it does not choose one.** It is the precondition for the downstream grilling ticket, which decides. Every external claim links to a primary source (Automerge docs, docs.rs for our pinned crate, the actual project repos/READMEs, nteract's source and blog); every stack claim links to the file or ADR in this repo.
>
> **Placement:** saved to `docs/research/` to match the on-disk convention of the other research notes (e.g. [`automerge-project-catalog.md`](automerge-project-catalog.md), [`automerge-conflict-representation.md`](automerge-conflict-representation.md)). That home is unsettled — [#208](https://github.com/zorn/local_cents/pull/208) stopped rendering these and [#209](https://github.com/zorn/local_cents/issues/209) is still deciding where they live — so treat the path as provisional.

## TL;DR

Today there is **exactly one** Automerge instance in the whole system. The Mac app's BEAM owns it: a per-Book `BookServer` GenServer holds the in-memory document and is the single source of truth ([ADR 0007](../adr/0007-book-runtime-and-persistence.md)). Both the native window **and** the browser tab are **thin LiveView clients of that same Phoenix server** — the browser is a supported second *client*, not a second *instance* ([ADR 0023](../adr/0023-browser-as-a-second-client.md)). It holds no document; it subscribes to the Book's PubSub topic and re-renders. So the browser as it stands **cannot demonstrate offline collaboration at all**: cut its link to the Mac's server and it does not keep working with a diverging local copy — the LiveView simply disconnects and stops rendering. There is nothing on the browser side to diverge.

That reframes the whole question. A genuine "two instances diverge, then reconcile" demo requires a **second place where a document actually lives and keeps accepting edits while the link is down.** There are three honest answers to *where* that second document lives, and they are the three architecture families below. The transport that carries changes between the two (whole-document `merge` vs. the Automerge sync protocol; Phoenix Channels vs. a raw socket vs. p2p) is a **second, largely independent axis** treated in section 5.

The one primitive we already have is `merge/2` — the [`ExAutomerge`](../lib/local_cents/tracking/ex_automerge.ex) NIF that combines two documents' bytes with no conflict (`native/ex_automerge/src/lib.rs`). We do **not** have the Automerge sync protocol wired up; that is a new NIF surface if we want it (section 5).

## 0. The current architecture, stated precisely (the baseline every option departs from)

- **One document, in the BEAM, via Rust.** `LocalCents.Tracking.BookServer` decodes the Book's bytes, applies each command through the pure `BookDocument` core, persists via `BookStore`, then broadcasts on `"book:<id>"` so subscribed LiveViews re-render ([`book_server.ex`](../lib/local_cents/tracking/book_server.ex)). The bytes are an Automerge CRDT produced by the `ExAutomerge` Rustler NIF binding the `automerge` Rust crate ([`ex_automerge.ex`](../lib/local_cents/tracking/ex_automerge.ex); crate pinned `automerge = "=0.10.0"` in `native/ex_automerge/Cargo.toml`).
- **The mutation path is `reconcile/3`; the combine path is `merge/2`.** Both are already-shipped NIFs. `merge/2` is described in the module as "the foundation for future multi-device sync" ([`ex_automerge.ex`](../lib/local_cents/tracking/ex_automerge.ex)).
- **Both clients hit the same server.** The Tauri shell spawns an ordinary Phoenix server on `127.0.0.1:4000`; the native window and a dev browser tab both load LiveView routes against it ([ADR 0023](../adr/0023-browser-as-a-second-client.md)). Views read a `@client` assign (`:desktop` or `:browser`) but share one `BookServer` and one document.
- **Persistence is a per-Book file on the Mac.** `.../books/<book-id>.lcbook`, loaded on open, written on change ([ADR 0007](../adr/0007-book-runtime-and-persistence.md)). ADR 0007 already flags that "a browser cannot read the user's local filesystem, so Book storage will have to move server-side" for any hosted web future — the same tension surfaces here.

The prior-art anchor for "do it properly" is **nteract 2.0**, our exact stack (Tauri + Automerge). Its frontend and its runtime daemon are **each their own Automerge peer**, both compiled from the same Rust `automerge` crate — the daemon natively, the frontend to WASM (`runtimed-wasm`: "WASM bindings … compiled from the same automerge crate as the daemon", [Cargo.toml](https://raw.githubusercontent.com/nteract/nteract/main/crates/runtimed-wasm/Cargo.toml)). They converge by exchanging **Automerge sync messages over a length-prefixed socket protocol** (Unix domain sockets / named pipes), **not** through Tauri IPC commands into a single Rust-held document ([nteract 2.0 blog](https://nteract.io/blog/nteract-2.0); source: [`notebook-sync/Cargo.toml`](https://raw.githubusercontent.com/nteract/nteract/main/crates/notebook-sync/Cargo.toml) depends on `automerge`, not `automerge-repo`). Crash isolation is the point they call out: "If the runtime goes down, it doesn't take your document down with it — you still have the copy you're editing" ([blog](https://nteract.io/blog/nteract-2.0)). That is the split-peer model Options A and B below reach for.

---

## Option A — Two BEAM peers; the browser stays a LiveView client of a *second* server

**Where the second document lives.** In a second BEAM, in its own `BookServer`, via the same `ExAutomerge` NIF. The "browser instance" is really *browser UI + a second Phoenix/BEAM behind it* — a second local app instance, or a hosted LocalCents server ([ADR 0023](../adr/0023-browser-as-a-second-client.md) notes a hosted LocalCents "now has a client to be"). The browser itself holds no CRDT; it stays a pure LiveView client, exactly as today, just pointed at the second server.

**Transport between the two instances.** Server-to-server. Either ship whole-document bytes and call the existing `merge/2` on receipt, or add the Automerge sync protocol as new NIFs (section 5) to ship only the delta. The socket can be a Phoenix Channel between the two endpoints, a bare WebSocket, distributed Erlang, or a p2p link (iroh/Subduction, section 5). nteract's model maps directly here — two Rust `automerge` peers exchanging sync messages — except the peers are two BEAMs rather than a daemon and a webview.

**Is the browser a genuine second instance?** Only transitively: the genuinely-separate document is the second BEAM's, and the browser is that BEAM's window onto it. For a demo run as "two app instances side by side" (two Macs, or Mac + hosted server viewed in a browser) this is faithful — each side keeps editing its own document while the link is down. For a demo that must be *literally* "a browser tab as the peer, with no second server," it is not (that is Option B).

**Fit with our stack.** Highest. Reuses `BookServer`, `BookDocument`, `ExAutomerge`, PubSub, the `@client` split — all unchanged. `merge/2` already exists. The new surface is only the inter-server transport and a reconcile trigger. It also lines up with the hosted-web direction ADR 0007 and ADR 0023 already anticipate.

**What the offline toggle gates.** The inter-server link only. Each BEAM keeps serving its own LiveView clients from its own `BookServer` throughout; offline just suspends the sync channel, edits diverge locally, and flipping back online runs the merge (or sync exchange) and re-broadcasts. Clean and honest: nothing local degrades when "offline."

**Cost / complexity.** Low-to-moderate. No new rendering path, no JS CRDT, no WASM. Main new work: stand up a second instance for the demo, a transport, and a "sync now / auto-sync" reconcile step. `merge/2`-over-a-socket is the minimal version and could be built in days.

**Main risks.** (1) The "browser as peer" framing is really "second server as peer" — if the map specifically wants a browser tab that works with its own local store, this does not deliver it. (2) Whole-document `merge` over the wire is O(document size) each sync; fine at MVP scale, wasteful later (the sync protocol fixes it, section 5). (3) A hosted second server reintroduces the "where do server-side books live" question ADR 0007 deferred.

---

## Option B — The browser is an independent Automerge peer (JS/WASM), holding its own document

**Where the second document lives.** In the browser tab, in a JavaScript/WASM Automerge engine, persisted to a browser store (IndexedDB via `automerge-repo-storage-indexeddb`, or OPFS via [`automerge-repo-storage-opfs`](https://github.com/openscript-ch/automerge-repo-storage-opfs) — note that adapter is **archived / read-only since Dec 2024**). Two sub-variants for the engine: use the JS `automerge` library, or compile **our** `ex_automerge` Rust crate to WASM so both peers run the identical core — the nteract approach ([runtimed-wasm](https://raw.githubusercontent.com/nteract/nteract/main/crates/runtimed-wasm/Cargo.toml)). Either way the browser is a genuinely separate instance in the literal sense the ticket asks about.

**Transport.** The Automerge sync protocol over a WebSocket or a Phoenix Channel between the browser's JS document and the BEAM's Rust document. The two engines are wire-compatible (same Automerge format), so cross-engine sync/merge works — this is exactly what nteract does across its native-Rust ↔ WASM boundary ([blog](https://nteract.io/blog/nteract-2.0)). The BEAM side needs either sync-protocol NIFs or a whole-document `merge/2` fallback (section 5).

**Is the browser a genuine second instance?** Yes — the strongest "yes" of the three. The document lives in the tab and keeps accepting edits with the network fully down.

**Fit with our stack.** Poor — this is the expensive option. A browser that edits a **local** document is no longer a server-rendered LiveView reading `BookServer` state; the UI must read and write the in-tab CRDT, i.e. a **client-side rendering path** alongside (or replacing) LiveView + Bond server components. That is a large departure from the current architecture and from [ADR 0023](../adr/0023-browser-as-a-second-client.md)'s "browser is a thin client" stance. It also means vendoring a JS/WASM CRDT into `assets/vendor/` (project convention is to avoid npm and vendor JS deps — see the repo's JS/CSS rules) or standing up a WASM build of our crate.

**What the offline toggle gates.** The browser↔BEAM channel. Offline, the browser edits its in-tab document with zero server involvement (true local-first); reconnect runs the sync exchange against the BEAM document. This is the most convincing offline story because the browser genuinely runs disconnected.

**Cost / complexity.** High. New client-side app/render path, a JS or WASM CRDT engine, a browser storage adapter, the sync-protocol wiring on both ends, and a second source of truth for the same UI. Weeks, not days, and it partially forks the front end.

**Main risks.** (1) Two rendering paths (LiveView server-side vs. client-side CRDT) is a lasting maintenance tax and a place the two clients drift — the exact drift ADR 0023 already worries about, amplified. (2) The OPFS adapter is archived; IndexedDB is the maintained browser-storage path. (3) There is **no mature Rust automerge-repo** to meet a JS `automerge-repo` browser peer in the middle (section 5), so we would either hand-roll the sync protocol on the Elixir side or run the browser against core `automerge` without the repo conveniences.

---

## Option C — Two in-process documents, toggle-gated `merge` (a faithful demo, not genuinely separate)

**Where the second document lives.** In the *same* BEAM, as a second `BookServer` (or a second document) standing in for "device 2." The native window views one; the browser tab views the other. No second machine, no network.

**Transport.** None over a wire. "Sync" is a direct `merge/2` call between the two in-process documents, triggered by a button or a timer.

**Is the browser a genuine second instance?** No — and this option does not pretend to be. It is a **simulation** of two instances for the purpose of demonstrating the *divergence-then-reconcile UX*, not the isolation. Both documents live in one process.

**Fit with our stack.** Trivial. Reuses everything; adds only a second `BookServer` wiring and a merge trigger. Nothing new crosses a process or machine boundary.

**What the offline toggle gates.** The automatic `merge/2` between the two in-process documents. Offline, the two are edited independently and kept apart; flipping online calls `merge` both directions and both windows re-broadcast. This gates a **simulated** partition, which is exactly what a debug/demo control is for.

**Cost / complexity.** Lowest — a day or two. It is the cheapest way to get the *conflict/merge UX* (the subject of the #211/#212/#214/#215 notes) in front of people without building any transport.

**Main risks.** It demonstrates the merge **behavior** but proves nothing about **isolation, transport, or real offline** — reviewers may read more into it than it shows. Best framed explicitly as a UX/behavior demo and a stepping stone, not the target architecture.

---

## 5. The transport axis (largely independent of A/B/C)

Two questions sit underneath every option above and can be decided separately.

**5a. Whole-document `merge` vs. the Automerge sync protocol.**

- **Whole-document `merge/2`** is what we already have: ship the full serialized document, call `merge/2` on receipt. Simplest; correct; O(document size) per sync regardless of how little changed. Good enough for a demo and for small Books.
- **The Automerge sync protocol** exchanges stateful sync messages so each side sends only the changes the other is missing. Each peer keeps a per-peer `State` that "tracks … what the heads of the other peer are"; the peers ping-pong `generate_sync_message` / `receive_sync_message` "until neither has anything new to send," over any **reliable, in-order** channel ([Automerge sync docs](https://automerge.org/automerge/automerge/sync/index.html); Rust `automerge::sync` — `State`, `SyncDoc`, `generate_sync_message`, `receive_sync_message` on [docs.rs](https://docs.rs/automerge/latest/automerge/sync/index.html)). It is **transport-agnostic** — the messages are opaque bytes. Adopting it means **new NIFs** exposing that Rust API through Rustler (we bind the same crate today, so this is additive, not a rewrite). Buys bandwidth efficiency; costs the NIF surface and per-peer state management.

**5b. What carries the bytes.** All of these are viable and mostly orthogonal to A/B/C:

| Transport | Layer | Language / fit | Central server? | Notes |
|---|---|---|---|---|
| **Phoenix Channels / WebSocket** | app socket | native to our stack | the Phoenix server | The obvious first choice for A and B; a Channel is a reliable in-order stream, which is all the sync protocol needs. |
| **Distributed Erlang** | BEAM-to-BEAM | native for Option A | no (mesh) | Only if both peers are BEAMs on a trusted network; not a browser answer. |
| **[iroh](https://docs.iroh.computer/) / [iroh-automerge](https://github.com/n0-computer/iroh-examples/tree/main/iroh-automerge)** | p2p QUIC transport | Rust (fits the NIF side) | no — direct p2p, relay only for NAT traversal | Example runs "automerge's sync protocol over an iroh QUIC connection"; nodes addressed by public key. Strong for *real* device-to-device sync later; a browser leg needs WASM. `iroh-automerge-repo` bridges to automerge-repo via `samod`. |
| **[Subduction / Sedimentree](https://github.com/inkandswitch/subduction)** | p2p encrypted sync protocol | Rust → WASM | no (optional hosted relay) | An *alternative* sync protocol for Automerge that diffs history metadata to ship only changed fragments; encrypted, serverless. Ink & Switch; README warns "early release preview … DO NOT use for production." Future-facing. |
| **[mergeparty](https://github.com/mycelial-systems/mergeparty)** | automerge-repo network+storage adapter | TypeScript | yes — Cloudflare PartyKit | Only relevant if the browser runs `automerge-repo` (Option B) and we accept a Cloudflare-hosted relay. Early-stage. |

**5c. The repo-layer gap that constrains B.** `automerge-repo` (the JS wrapper adding many-document management, pluggable [network adapters](https://automerge.org/docs/reference/repositories/networking/) — WebSocket, MessageChannel, BroadcastChannel — and [storage adapters](https://github.com/automerge/automerge-repo) — IndexedDB, Node FS) is **JavaScript-first**. On the Rust/BEAM side there is **no mature, JS-compatible repo layer** as of 2026: `automerge/automerge-repo-rs` is explicitly "**not compatible**" on wire/disk with the JS implementation ([README](https://github.com/automerge/automerge-repo-rs)), and the compatible successor [`samod`](https://github.com/alexjg/samod) is "an experimental implementation … very much a work in progress." So an Option B browser running JS `automerge-repo` would **not** find a ready Elixir/Rust repo peer to talk to — we would hand-roll the core sync protocol on the Elixir side (5a) or run the browser against core `automerge` without the repo conveniences. This is the single biggest hidden cost in Option B.

---

## 6. Comparison

| Axis | A — Two BEAM peers | B — Browser JS/WASM peer | C — Two in-process docs |
|---|---|---|---|
| Where the 2nd doc lives | second BEAM (`BookServer`, Rust NIF) | browser tab (JS or WASM Automerge + IndexedDB/OPFS) | same BEAM, 2nd `BookServer` |
| Browser is… | a LiveView client of the 2nd server | a genuine independent peer | a LiveView client (of the 2nd in-proc doc) |
| Genuinely separate instances? | yes, but the peer is a *server*, not the tab | yes, literally the tab | no — simulated |
| Transport | server↔server (Channel / dist-Erlang / p2p) | browser↔BEAM (Channel/WS, sync protocol) | none (in-process `merge`) |
| Reuses `BookServer`/`ExAutomerge`? | fully | BEAM side yes; browser side new engine | fully |
| New rendering path? | no | **yes** (client-side CRDT UI) | no |
| Offline toggle gates | inter-server link | browser↔BEAM channel | automatic in-process `merge` |
| Cost | low–moderate | high | lowest |
| Best for | a real two-instance demo + hosted-web direction | a literal offline *browser* peer | a fast UX/behavior demo of divergence+merge |

## 7. Open questions for the decision

1. **What must the demo literally show?** "Two app instances reconcile" (Option A satisfies) vs. "a browser tab, with its own local store, works while offline" (only Option B satisfies). The map's intent here decides between A and B and is the pivotal question.
2. **Is a stepping-stone acceptable?** Option C ships the divergence-then-merge **UX** in days and de-risks the conflict-surfacing work (#211/#212) without any transport. Is a labeled simulation a useful first deliverable, or does the demo have to be genuinely partitioned from the start?
3. **`merge` now or the sync protocol now?** Whole-document `merge/2` is already built and adequate for demo-scale Books; the sync protocol is a new NIF surface bought only for bandwidth. Does the demo need the efficient path, or is that deferrable?
4. **If Option B: which engine and store?** JS `automerge` vs. compiling our own `ex_automerge` crate to WASM (nteract's identical-core approach); IndexedDB (maintained) vs. OPFS (archived adapter). And are we willing to carry a client-side rendering path beside LiveView?
5. **Where do second-instance Books live?** A hosted second server (Option A) or any server-side peer reopens the "browser can't read the local filesystem, storage moves server-side" question ADR 0007 explicitly deferred. Does the demo force that decision early?
6. **Transport for the real future, not just the demo:** if device-to-device p2p (iroh/Subduction) is the eventual target, does that argue for building the demo on the sync protocol over a Channel now, so the transport can be swapped under a stable sync layer later?

## Sources

- Our runtime & stack — [ADR 0007](../adr/0007-book-runtime-and-persistence.md), [ADR 0023](../adr/0023-browser-as-a-second-client.md), [`book_server.ex`](../lib/local_cents/tracking/book_server.ex), [`ex_automerge.ex`](../lib/local_cents/tracking/ex_automerge.ex), `native/ex_automerge/src/lib.rs`, `native/ex_automerge/Cargo.toml`
- Prior catalog & conflict notes — [`automerge-project-catalog.md`](automerge-project-catalog.md) (issue [#216](https://github.com/zorn/local_cents/issues/216)), [`automerge-conflict-representation.md`](automerge-conflict-representation.md)
- nteract 2.0 (Tauri + Automerge, split-peer) — [blog](https://nteract.io/blog/nteract-2.0), [runtimed-wasm Cargo.toml](https://raw.githubusercontent.com/nteract/nteract/main/crates/runtimed-wasm/Cargo.toml), [notebook-sync Cargo.toml](https://raw.githubusercontent.com/nteract/nteract/main/crates/notebook-sync/Cargo.toml), [repo](https://github.com/nteract/nteract)
- Automerge sync protocol — [automerge.org sync docs](https://automerge.org/automerge/automerge/sync/index.html), [docs.rs automerge::sync](https://docs.rs/automerge/latest/automerge/sync/index.html)
- automerge-repo — [repo/README](https://github.com/automerge/automerge-repo), [networking reference](https://automerge.org/docs/reference/repositories/networking/); Rust repo layer — [automerge-repo-rs](https://github.com/automerge/automerge-repo-rs), [samod](https://github.com/alexjg/samod)
- Transport prior art — [iroh](https://docs.iroh.computer/) / [iroh-automerge examples](https://github.com/n0-computer/iroh-examples/tree/main/iroh-automerge), [Subduction](https://github.com/inkandswitch/subduction) & [subduct.io](https://subduct.io/), [mergeparty](https://github.com/mycelial-systems/mergeparty), [automerge-repo-storage-opfs](https://github.com/openscript-ch/automerge-repo-storage-opfs) (archived)
