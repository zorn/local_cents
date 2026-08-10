# Two-Peer Sync Architecture

## Problem Statement

The offline-collaboration demo we are building toward is: create an expense, take the Mac app offline, edit its description on both the Mac app and the browser, come back online, and watch LocalCents reconcile the two edits. That demo needs two instances that genuinely diverge while the link is down and then merge — but today there is **exactly one** Automerge document in the whole system.

The Mac app's BEAM owns it: a per-Book `LocalCents.Tracking.BookServer` holds the in-memory document and is the single source of truth ([ADR 0007](0007-book-runtime-and-persistence.md)). Both the native window and a browser tab are thin LiveView clients of that same Phoenix server — the browser is a supported second *client*, not a second *instance* ([ADR 0023](0023-browser-as-a-second-client.md)). It holds no document; it subscribes to the Book's PubSub topic and re-renders. So the browser as it stands cannot demonstrate offline collaboration at all: cut its link and the LiveView simply disconnects. There is nothing on the browser side to diverge.

A genuine "two instances diverge, then reconcile" demo therefore requires a second place where a document actually lives and keeps accepting edits while the link is down. The research note behind [issue #222](https://github.com/zorn/local_cents/issues/222) laid out three families by *where* that second document lives, and this decision picks among them.

## Decision Made

**Two BEAM peers, syncing over the Automerge sync protocol.** The Mac app keeps its embedded BEAM and its `BookServer`-owned document. A **second, plain local Phoenix server** — a separate OS process on its own port, with no Tauri shell — owns a second document, and the browser is that server's always-online LiveView client. The two BEAMs are the two instances; the browser stays a thin client of the second one, exactly as it is a thin client of the first today.

The moving parts:

- **The offline toggle lives on the Mac side only.** It is a debug control in the Mac app that suspends the sync link between the two BEAMs. The browser's second BEAM is always online; only the Mac goes offline. While the link is down the two documents accept edits independently; flipping back online runs the sync exchange and both windows re-broadcast the reconciled result.
- **Transport is the Automerge sync protocol, exposed through new Rustler NIFs.** Each peer keeps a per-peer sync `State` and exchanges stateful sync messages so only the missing changes cross the wire. This is additive to the existing `ExAutomerge` NIF, which already binds the same `automerge` crate; the shipped whole-document `merge/2` primitive stays as the combine foundation but is not what the demo runs on.
- **The messages ride a WebSocket / Phoenix Channel between the two BEAMs.** A Channel is a reliable, in-order stream, which is all the sync protocol needs, and it is the same transport a future hosted or remote peer would use — so it is not throwaway demo scaffolding.
- **A single command brings the demo up.** One entrypoint boots both instances, **seeds** the second BEAM with the current Book over the sync link so both start from a common ancestor, connects them, opens the browser, and tears both down on exit. Seeding is folded into the launcher so no document is ever hand-copied between instances.

Each BEAM keeps its own local `.lcbook` file, so this **does not** force the server-side Book storage question [ADR 0007](0007-book-runtime-and-persistence.md) deferred — that stays deferred.

This choice is the first leg of the real product, not demo-only scaffolding: a hosted LocalCents, a self-hosted instance, and the Mac app's embedded BEAM are all BEAM peers that reconcile server-to-server through this same path. In that world the browser staying a thin LiveView client is correct, not a compromise ([ADR 0023](0023-browser-as-a-second-client.md)).

## Consequences & Tradeoffs

* **Rejected: the browser as an independent JS/WASM Automerge peer** holding its own in-tab document (IndexedDB/OPFS). It is the only option that makes a browser tab work with the network fully down, but it forces a client-side rendering path alongside LiveView + Bond server components — a lasting maintenance tax and the exact client drift [ADR 0023](0023-browser-as-a-second-client.md) already worries about — and there is no mature, JS-compatible Rust `automerge-repo` for the BEAM side to meet it. That cost only buys a literally-offline *browser*, which the product does not need: the offline-capable client is always the Tauri app, and pure-web users being online-only is a coherent local-first stance. This flips only if "a browser tab that keeps working with no server behind it" becomes an explicit product goal.
* **Rejected: two in-process documents with a toggle-gated `merge/2`** — a second `BookServer` in the same BEAM standing in for "device 2," reconciled by a direct in-process `merge`. It is the cheapest way to get the divergence-then-merge UX in front of people, but it is a simulation: it proves nothing about isolation, transport, or real offline. We chose not to build demo-only scaffolding that has to be discarded once the real transport lands.
* **Rejected: whole-document `merge/2` as the demo transport.** It is already shipped and adequate at Book scale, but it ships the full document every sync regardless of how little changed. We chose the sync protocol instead so the demo runs on the real delta-based layer, and so a future device-to-device p2p transport (iroh, Subduction) can swap under a stable sync layer without redoing the reconcile path. The cost is the new NIF surface and per-peer state management.
* **Accepted:** the second BEAM is a second running instance to stand up and manage for the demo, and the one-command launcher that boots, seeds, connects, and tears down both is real work — but folding it into a single command is what keeps the demo a one-liner rather than a sequence of hand-run steps.
* **Deferred:** the modeling of *how conflict metadata surfaces* from Automerge up through `ExAutomerge` into LiveView, and the conflict UI itself, are settled elsewhere ([issue #220](https://github.com/zorn/local_cents/issues/220) prototype). This decision is only about isolation and transport.
