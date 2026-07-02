# Automerge Rust Library

## Problem Statement

LocalCents will [Automerge](https://automerge.org/) as its core data storage system to enable local-first, offline-capable, syncing across desktop, web, and (eventually, maybe) mobile clients. Calls into the [Rust](https://rust-lang.org/) Automerge library will happen from [Elixir](https://elixir-lang.org/) into Rust via [Rustler](https://github.com/rusterlium/rustler). The decision before us is which Rust-side library to call.

The core [`automerge`](https://github.com/automerge/automerge) crate exists but its README [explicitly steers](https://github.com/automerge/automerge#rust) Rust users elsewhere:

> The rust codebase is currently oriented around producing a performant backend for the Javascript wrapper and as such the API for Rust code is low level and not well documented. We will be returning to this over the next few months but for now you will need to be comfortable reading the tests and asking questions to figure out how to use it. If you are looking to build rust applications which use automerge you may want to look into [autosurgeon](https://github.com/automerge/autosurgeon).

Autosurgeon is a Rust library for working with data in automerge documents in a Rust environment. It provides a more ergonomic API for working with automerge documents.

While autosurgeon is explicitly mentioned in the main automerge README, a newer alternative, [`automorph`](https://codeberg.org/dpp/automorph) is available as well. Automorph details its conceptual differences to autosurgeon in a detailed [conceptual comparison](https://codeberg.org/dpp/automorph/src/branch/main/docs/migration/concepts.md) document. Automorph has some interesting design choices, offering "bidirectional workflows", "tools for observing", and treating "document as a persistent data structure".

## Decision

As a Rust noob, I think I will get good value from a library designed to provide a friendly API for calling automerge core instead of reaching into automerge core directly. While I admire some of the design philosophies of automorph, it is a much younger project, and I think I'd prefer the maturity of autosurgeon, which is officially supported by the Automerge GitHub organization, and its overall design preferences (which I think align better with this project).

## Other Notes

Separately, the Automerge ecosystem has a "repo" layer that bundles storage, sync protocol, and document registry: [`automerge-repo`](https://github.com/automerge/automerge-repo) (TypeScript), [`automerge-repo-rs`](https://github.com/automerge/automerge-repo-rs) (older Rust), and [`samod`](https://github.com/alexjg/samod) (a newer Rust implementation intended to replace `automerge-repo-rs`).

We are **not** adopting `samod` or `automerge-repo-rs` for v1. Instead, Elixir will own the responsibilities that repo libraries would otherwise provide, using GenServers and Registries to manage document handles and Phoenix Channels for communication.

Rust use will stay narrow: pure CRDT operations on document bytes. This keeps the NIF surface small (good for the BEAM scheduler), avoids embedding a separate async runtime inside Rustler, and reuses BEAM's strengths in networking and process supervision.
