# Which Automerge Rust Library to Use

## Problem Statement

This project wants to utilize [Automerge](https://automerge.org/) as a persistent storage system allowing for local-first syncing. We have a way to call Rust from Elixir via Rustler. The decision before us is what Automerge code do we want to call.

The main repo at <https://github.com/automerge/automerge> is at noted in the README:

> The rust codebase is currently oriented around producing a performant backend for the Javascript wrapper and as such the API for Rust code is low level and not well documented. We will be returning to this over the next few months but for now you will need to be comfortable reading the tests and asking questions to figure out how to use it. If you are looking to build rust applications which use automerge you may want to look into autosurgeon.

The aforementioned `autosurgeon` <https://github.com/automerge/autosurgeon> is a valid option to consider but in more recent times another library has been developed called `automorph` <https://codeberg.org/dpp/automorph>

The `automorph` project provides a conceptual comparison here: <https://codeberg.org/dpp/automorph/src/branch/main/docs/migration/concepts.md>

## Open Questions

- I'm still fuzzy on what logic is in these automerge "core" libraries and what else I'll need related to the "repo" liberties <https://github.com/automerge/automerge-repo> (TypeScript), <https://github.com/alexjg/samod> (Rust implementation).
