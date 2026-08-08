# Automerge & CRDT / Local-First Project Catalog

> Standing inventory feeding [issue #216](https://github.com/zorn/local_cents/issues/216). This is a **catalog** — a list of who is building in our problem space — not an analysis. It complements two prior notes and does not repeat them: the UX-presentation survey ([#212](https://github.com/zorn/local_cents/issues/212)) covers *how* these projects present sync/conflict state to users, and the conflict-representation note ([#211](https://github.com/zorn/local_cents/issues/211)) covers *how* conflicts are modeled. Where a project is notable for its UX, this note points at it and defers the treatment to #212.

## Scope and method

Two lists:

1. **Automerge-based projects** — anything built on Automerge, any language binding.
2. **Other CRDT / local-first projects** — Yjs, Loro, iroh, custom CRDTs. Not Automerge, but the same problem space, still worth tracking.

Every seed link from #216 is triaged below (into list 1, list 2, or not-relevant with a reason). Discovery then went beyond the seeds via GitHub `topic:automerge` / `topic:crdt` / `topic:local-first`, the Ink & Switch project index, `crdt.tech`, `awesome-crdt` / `awesome-local-first`, and the Yjs / Loro / iroh ecosystems.

**Provenance caveat:** the seed links were captured from the Automerge Discord `#look-what-i-made` channel, which is login-gated. These seeds partly fill that gap, but the full channel was **not** crawled — treat the seed set as a sample, not a census.

**Column meaning.** *Inspectable* = can we read the source and/or poke a live demo. "Source" = public repo. "Demo" = a running instance a browser can reach.

---

## List 1 — Automerge-based projects

### From the seed links

| Project | Tech | Inspectable | Why it's interesting |
|---|---|---|---|
| [TeamSketchbook](https://www.teamsketchbook.com/) | Automerge (via MindooDB) | Live product (freemium); app closed-source, DB open | Collaborative sketching/annotation; explicitly cites Automerge for merging concurrent tablet/phone edits into one image. A shipped commercial local-first product. |
| [automerge-lexical-plugin](https://github.com/rohankshah/automerge-lexical-plugin) | Automerge + Lexical | Source + local playground | Binds Automerge to Meta's Lexical rich-text editor. A rich-text-binding reference point. |
| [philschatz/drive](https://github.com/philschatz/drive) | Automerge (`automerge-repo` over WebSocket) + Keyhive E2E | Source + [live demo](https://philschatz.com/drive) | Installable (PWA) collaborative editor with Calendar / Spreadsheet / Task-List doc types, offline-capable, end-to-end encrypted. Broad multi-doc-type app on our exact stack idea. |
| [Subduction / subduct.io](https://subduct.io/) | Sync protocol *for* Automerge (Sedimentree) | Source (MIT/Apache) + hosted service | P2P encrypted sync between peers with no central server; "first-class" Automerge integration, syncs by comparing history metadata rather than shipping whole docs. Directly relevant to our future sync layer. |
| [tarstate](https://github.com/neftaly/tarstate) | Pluggable; ships an Automerge adapter | Source | "Relational programming for React" — SQL-style queries over a state tree via incremental view maintenance, with an Automerge database adapter. A query-layer-over-CRDT idea. |
| [Ducking](https://www.adamsolove.com/ui/ducking/2026/06/10/podcast-multiplayer.html) | Automerge | Write-up only (no repo/demo linked) | Multiplayer podcast editor; the post is a hands-on experience report on data modeling, list reordering, rich text, and history in Automerge. Strong UX + data-modeling material — see #212 for the UX treatment. |
| [MindooDB / Haven](https://www.mindoodb.com/) | Automerge-based merging (incl. rich-text CRDT 2.2) | Source ([klehmann/MindooDB](https://github.com/klehmann/MindooDB), Apache 2.0) + [demo](https://haven.mindoodb.com) | Open-source E2E-encrypted local-first sync DB powering the Haven workspace; a [blog post](https://mindoodb.com/blog/2026/05/25.05.2026123000KLETE2/) details `.docx` editing bridged onto Automerge rich text. Underpins TeamSketchbook. |
| [Probability SDK](https://dev.probability.nz/sdk/react/readme/) | Automerge (`automerge-repo`) | Source ([probability-nz/sdk](https://github.com/probability-nz/sdk)) + example plugin | React SDK for building plugins on the Probability game platform; uses Automerge sync with schema validation on the hot path. (Seed URL `probability-nz.github.io/...` 301-redirects to `dev.probability.nz`.) |
| [nteract 2.0](https://nteract.io/blog/nteract-2.0) | Automerge | Blog announcement | Notebook app rebuilt in **Rust + TypeScript on Tauri**, using Automerge for local-first notebooks (instant edit, crash recovery, human/AI collaboration). Closest architectural mirror of LocalCents (Tauri + Automerge) in this catalog. Note: the [main nteract site](https://www.nteract.io/) still describes the older desktop notebook and does not mention Automerge. |
| [automerge-pandoc](https://github.com/oktana-coop/automerge-pandoc) | Automerge | Source (Haskell) | CLI converting Automerge rich text to/from Pandoc formats (Markdown, HTML, JSON). Useful for import/export off an Automerge doc. |
| [automerge-inspector](https://github.com/cscheid/automerge-inspector) | Automerge (tooling) | Source (React) | Web debugger for inspecting Automerge **sync-protocol** message exchange. A dev/observability tool we may want when building sync. |
| [OnlyGroceries](https://github.com/nonscalable/OnlyGroceries) | Automerge (main branch) | Source + [demo](https://onlygroceries.pages.dev) | Minimalist local-first grocery list on **Tauri + Svelte**, using a public Automerge sync server. Small, readable, same stack family as us. (Its `iroh` branch is an experiment migrating off Automerge — see List 2.) |

### From beyond the seed links

| Project | Tech | Inspectable | Why it's interesting |
|---|---|---|---|
| [teamtype](https://github.com/teamtype/teamtype) | Automerge | Source (~1.9k★) | Peer-to-peer, editor-agnostic collaborative editing of local text files. Most-starred `topic:automerge` repo. |
| [DXOS / Composer](https://github.com/dxos/dxos) | Automerge (under the ECHO database) | Source | TypeScript protocol stack + SDK + the Composer app for local-first collaborative apps. A full platform built on Automerge. |
| [Automerge-Swift + MeetingNotes](https://github.com/automerge/automerge-swift) | Automerge | Source (official) | Official Swift bindings; [MeetingNotes](https://github.com/automerge/MeetingNotes) is the reference collaborative note-taking app, and [automerge-repo-swift](https://github.com/automerge/automerge-repo-swift) adds multi-doc networking/storage. Relevant to any Apple-platform surface. |
| [local-first-web/state](https://github.com/local-first-web/state) | Automerge | Source | Redux-style state container that syncs via Automerge (formerly Cevitxe). Framework-integration reference. |
| [effect-local](https://github.com/lucas-barake/effect-local) | Automerge + SQLite | Source | Local-first engine on Effect v4 with Automerge + SQLite replicas. Shows Automerge paired with a SQL store. |
| [automerge-jumpstart](https://github.com/nikgraf/automerge-jumpstart) | Automerge + React + tRPC | Source | Boilerplate/starter for real-time collaborative apps. Good "how do the pieces fit" reference. |
| [autowiki](https://github.com/nornagon/autowiki) | Automerge | Source | Personal networked-documents (wiki) tool. |
| [solid-automerge](https://github.com/chee/solid-automerge) | Automerge | Source | Fine-grained reactive Automerge bindings for SolidJS. |
| [Backstitch](https://github.com/inkandswitch/backstitch) | Automerge | Source (Ink & Switch) | Real-time version control for the Godot game engine. |
| [darn](https://github.com/inkandswitch/darn) | Automerge | Source (Ink & Switch) | Track, merge, and replicate files across peers with no central server. |
| [Ink & Switch prototypes](https://www.inkandswitch.com/) | Automerge (mostly) | Mostly source/essays | The research lab behind Automerge. Notable projects: **Patchwork** (version control for creative work), **Pushpin** (p2p canvas workspace), **Trellis** (Trello-like), **PixelPusher** (multiuser pixel art), **Capstone**, **Upwelling**, **Peritext** (rich-text CRDT algorithm), **Cambria** (doc schema migration), **Keyhive** (local-first access control + E2E). Primary source of prior-art thinking. |
| [automerge-r](https://github.com/posit-dev/automerge-r) | Automerge | Source | R bindings (by Posit). Shows the breadth of language bindings. |
| [vgg_automerge](https://github.com/verygoodgraphics/vgg_automerge) | Automerge | Source | A C++ implementation of Automerge. |
| [mergeparty](https://github.com/mycelial-systems/mergeparty) | Automerge + PartyKit | Source | Automerge sync over Cloudflare PartyKit. A sync-transport option. |
| [automerge-repo-storage-opfs](https://github.com/openscript-ch/automerge-repo-storage-opfs) | Automerge | Source | OPFS (browser Origin-Private File System) storage adapter for Automerge Repo. |
| [iroh-automerge examples](https://github.com/n0-computer/iroh-examples/tree/main) | Automerge over iroh transport | Source | `iroh-automerge` / `iroh-automerge-repo` show syncing Automerge over iroh's p2p layer; `tauri-todos` shows iroh documents in Tauri. Bridges Lists 1 and 2 (seed link). |
| [GoodNotes](https://automerge.org/) / [Bowtie](https://automerge.org/) | Automerge | Commercial, closed | Named on automerge.org as commercial users funding development. GoodNotes is a large-scale note-taking app — evidence Automerge is production-viable at scale. |
| [Archbee](https://crdt.tech/implementations) | Automerge (per crdt.tech) | Commercial, closed | Engineering-docs / knowledge tool. |

---

## List 2 — Other CRDT / local-first projects (not Automerge)

### Yjs ecosystem

| Project | Tech | Inspectable | Note |
|---|---|---|---|
| [Yjs](https://github.com/yjs/yjs) | Yjs CRDT | Source (~22k★) | The dominant non-Automerge CRDT for collaborative editing. |
| [y-crdt / y-octo](https://github.com/y-crdt/y-crdt) | Yjs (Rust port) | Source | Rust implementation of Yjs; relevant if comparing Rust CRDT cores. |
| [y-prosemirror](https://github.com/yjs/y-prosemirror) | Yjs + ProseMirror | Source | Offline p2p collaborative editing binding. Seed link [PR #217](https://github.com/yjs/y-prosemirror/pull/217) is a rewrite-goals doc. |
| [Hocuspocus](https://github.com/ueberdosis/hocuspocus) | Yjs | Source | The standard Yjs WebSocket sync backend. |
| [SyncedStore](https://github.com/YousefED/SyncedStore) | Yjs | Source | Ergonomic reactive store over Yjs. |
| [y-sweet](https://github.com/jamsocket/y-sweet) | Yjs | Source | Yjs sync server backed by S3. |
| [AFFiNE / BlockSuite / OctoBase](https://github.com/toeverything/AFFiNE) | Yjs (OctoBase = Rust) | Source | Notion/Miro-style knowledge base; BlockSuite is its editor toolkit, OctoBase its Rust local-first data engine. |
| [Liveblocks](https://github.com/liveblocks/liveblocks) | Yjs-compatible | Source + hosted | Commercial realtime-multiplayer infrastructure. |
| [mutxt.com](https://mutxt.com) | Yjs + Peritext | Live app ([via awesome-crdt](https://github.com/alangibson/awesome-crdt)) | Polished local-first rich-text editor using the Peritext rich-text CRDT. Cited for UX polish. |

### Loro ecosystem

| Project | Tech | Inspectable | Note |
|---|---|---|---|
| [Loro](https://github.com/loro-dev/loro) | Loro CRDT (Rust; JS/Swift bindings) | Source (~6k★) + playground | Rust CRDT with rich text, movable tree, and time-travel/version-control; the main modern alternative to Automerge for an app like ours. |

### iroh ecosystem

| Project | Tech | Inspectable | Note |
|---|---|---|---|
| [iroh](https://www.iroh.computer/) | P2P networking stack + CRDT "Documents" protocol | Source | Not a CRDT itself — a p2p connectivity/sync layer (by n0-computer). Can carry Automerge (see List 1) or its own Documents. Relevant as a transport for our sync. |
| [OnlyGroceries `iroh` branch](https://github.com/nonscalable/OnlyGroceries/tree/iroh) | iroh (experiment) | Source | Seed links point here: an experiment migrating the grocery app's sync from Automerge to iroh. A real "we swapped the sync layer" case study. Files: [layout.svelte](https://github.com/nonscalable/OnlyGroceries/blob/iroh/web/src/layout.svelte), [node.rs](https://github.com/nonscalable/OnlyGroceries/blob/iroh/src-tauri/src/node.rs), [iroh-network-adapter](https://github.com/nonscalable/OnlyGroceries/tree/iroh/web/src/lib/core/iroh-network-adapter). |

### Other CRDTs / local-first sync engines

| Project | Tech | Inspectable | Note |
|---|---|---|---|
| [Actual](https://actualbudget.org/) | Custom timestamp-based CRDT (hybrid logical clocks) | Source | **Local-first budgeting/expense app** — the single closest domain match to LocalCents. Worth studying for data model and sync UX regardless of the different CRDT. |
| [diamond-types](https://github.com/josephg/diamond-types) | Custom (fastest text CRDT) | Source | Research-grade high-performance text CRDT by Seph Gentle. |
| [json-joy](https://github.com/streamich/json-joy) | JSON CRDT | Source | High-performance JSON + rich-text CRDT and spec. |
| [cr-sqlite](https://github.com/vlcn-io/cr-sqlite) | CRDT extension for SQLite | Source | Multi-writer/CRDT SQLite — the "put CRDTs in your existing DB" approach. |
| [ElectricSQL](https://github.com/electric-sql/electric) | Postgres sync (rich-CRDT lineage) | Source | Sync engine layering local-first over Postgres. |
| [RxDB](https://github.com/pubkey/rxdb) | Replication protocol (CRDT optional) | Source | Local-first JS database with pluggable replication. |
| [TinyBase](https://github.com/tinyplex/tinybase) | Reactive store + sync engine | Source | Small reactive data store with a sync engine. |
| [Triplit](https://github.com/aspen-cloud/triplit) | Syncing database | Source | Full-stack client+server syncing DB. |
| [Evolu](https://github.com/evoluhq/evolu) | SQLite + CRDT | Source | Local-first platform emphasizing privacy / no lock-in. |
| [Jazz](https://github.com/garden-co/classic-jazz) | Custom CRDT ("CoValues") | Source | Distributed-across-the-stack database with its own CRDT model. |
| [Fireproof](https://github.com/fireproof-storage/fireproof) | CRDT-ish browser DB | Source | Embedded browser database that syncs anywhere. |
| [Fluid Framework](https://github.com/microsoft/FluidFramework) | Custom (OT/CRDT hybrid) | Source | Microsoft's distributed collaborative-app framework. |
| [Gun](https://github.com/amark/gun) | Graph CRDT | Source | Decentralized graph-sync protocol. |
| [OrbitDB](https://github.com/orbitdb/orbitdb) | CRDT over IPFS | Source | Peer-to-peer databases for the decentralized web. |
| [Mapeo](https://github.com/digidem/mapeo-core) | Hypercore/kappa CRDT (not Automerge) | Source | Offline mapping for indigenous land rights; a serious offline-sync field-tested app. |
| [NextGraph](https://nextgraph.org/) | CRDT + Semantic Web | Source | Encrypted collaborative semantic-web framework. |
| [Colanode](https://github.com/colanode/colanode) | Local-first (CRDT) | Source | Open-source local-first Slack/Notion alternative. |
| [Yorkie](https://github.com/yorkie-team/yorkie) | Custom CRDT | Source | Document store for collaborative editing apps. |

---

## Not relevant (triaged out, with reasons)

Seed links that are **not** CRDT/local-first projects, kept here so they aren't silently dropped:

| Link | Verdict |
|---|---|
| [gritzko/beagle](https://github.com/gritzko/beagle) | **Not CRDT.** A git-compatible source-control system redesigned for LLM-era, parallel-worktree development. (Author gritzko is a known CRDT author — RON / Swarm.js — but *this* project isn't CRDT.) |
| [replicated.live/blog/away](https://replicated.live/blog/away) | **Not CRDT.** A blog post about automating dev work with Claude, wrapping LLM non-determinism in the deterministic Beagle SCM tooling above. Despite the "replicated" domain, no replication/CRDT content. |
| [gritzko gist (scmandllm)](https://gist.github.com/gritzko/6e81b5391eacb585ae207f5e634db07e) | **Borderline / proposal only.** An essay proposing a future CRDT + AST-aware source-control system ("a database for the code"). Aspirational, not a usable project — noted, not cataloged. |
| [putt.day](https://putt.day/) | **Not relevant.** A daily mini-golf browser game. No CRDT/sync. |
| [encribe.com](https://encribe.com/) | **Ambiguous — no CRDT confirmed.** A writing platform with keystroke-biometric authorship proof; mentions "offline writing with device sync" but names no CRDT/Automerge/local-first tech. Flagged, not cataloged. |
| [adamsolove …/better-podcast-ui](https://www.adamsolove.com/ui/ducking/2026/06/03/better-podcast-ui.html) | **Not CRDT (companion piece).** UI-design article for the Ducking podcast editor; only the [multiplayer post](https://www.adamsolove.com/ui/ducking/2026/06/10/podcast-multiplayer.html) (cataloged in List 1) covers Automerge. |
| [github.com/c4lliope](https://github.com/c4lliope) | **Not relevant.** A developer profile with no CRDT/local-first repos surfaced. |
| [quarto-dev/q2](https://github.com/quarto-dev/q2) | **Not CRDT.** Experimental Rust rewrite of the Quarto publishing framework. No CRDT/local-first. |

Two seed links are **relevant context but not standalone projects** (so cross-referenced above rather than listed):

- [jgm/pandoc discussion #11443](https://github.com/jgm/pandoc/discussions/11443) — a proposal to add Automerge + ProseMirror + doc-diffing to Pandoc. Context for [automerge-pandoc](https://github.com/oktana-coop/automerge-pandoc) (List 1), not itself a project.
- [yjs/y-prosemirror PR #217](https://github.com/yjs/y-prosemirror/pull/217) — a rewrite-goals doc, folded into the y-prosemirror row (List 2).

---

## Counts

- **List 1 (Automerge):** ~30 projects (12 from seeds + ~18 discovered; Ink & Switch counted as one cluster covering ~9 sub-prototypes).
- **List 2 (other CRDT / local-first):** ~30 projects across the Yjs, Loro, iroh, and custom-CRDT ecosystems.
- **Not relevant / non-project:** 8 seed links triaged out (5 not-relevant, 1 ambiguous with no confirmed CRDT, 2 relevant-context discussions cross-referenced).
- **Dead links:** none. One redirect (`probability-nz.github.io` → `dev.probability.nz`, noted inline).

## Standouts for LocalCents

1. **nteract 2.0** — Tauri + Automerge, the same architecture we chose; watch it.
2. **Actual** — a local-first *budgeting/expense* app; closest domain twin, even though it uses a custom CRDT rather than Automerge.
3. **Subduction, mergeparty, iroh-automerge, automerge-repo-storage-opfs** — concrete options and prior art for the sync/transport/storage layer we have not built yet.
4. **OnlyGroceries** — a small Tauri+Svelte Automerge app *and* a documented experiment swapping Automerge for iroh; readable end-to-end.
5. **Loro** — the strongest non-Automerge alternative core, with built-in time travel; a useful comparison benchmark.
