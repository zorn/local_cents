# Command Line History

A place to record generator or other prompts used to create notable files.

## July 2, 2026

Installed a set of Claude Code agent skills. The skills and their install instructions are recorded in this gist:

https://gist.github.com/zorn/e5996736f32117bed583d3055c1441d9

## June 5, 2026

Ran `mix phx.gen.storybook` as part of:

https://phoenix-storybook.hexdocs.pm/PhoenixStorybook.html#module-2-run-the-generator

## May 27, 2026

Working through [this tutorial](https://fly.io/phoenix-files/elixir-and-rust-is-a-good-mix/) and ran `mix rustler.new`.

```
$ mix rustler.new
This is the name of the Elixir module the NIF module will be registered to.
Module name > LocalCents.ExAutomerge
This is the name used for the generated Rust crate. The default is most likely fine.
Library name (localcents_exautomerge) > ex_automerge
Fetched latest rustler crate version: 0.38.0
* creating native/ex_automerge/README.md
* creating native/ex_automerge/Cargo.toml
* creating native/ex_automerge/src/lib.rs
* creating Cargo.toml
Updating .gitignore file
```

## May 24, 2026

Update Rust (I had it previously installed) with:

```
rustup update
```

https://rust-lang.org/tools/install/

The prerequisites for Tauri on macOS include Xcode (which I already have, version 16.4).

https://tauri.app/start/prerequisites/

Generator for Tauri app, 

https://hexdocs.pm/elixirkit/tauri.html#tauri

```
[zorn@Chrono ~/Desktop> sh (curl -sSL https://create.tauri.app/sh | psub)
info: downloading create-tauri-app
✔ Project name · local-cents
✔ Identifier · com.example.LocalCents
✔ Choose which language to use for your frontend · Rust - (cargo)
✔ Choose your UI template · Vanilla

Template created! To get started run:
  cd local-cents
  cargo tauri android init
  cargo tauri ios init

For Desktop development, run:
  cargo tauri dev

For Android development, run:
  cargo tauri android dev

For iOS development, run:
  cargo tauri ios dev
)
```

## May 24, 2026

New Phoenix Project

```
mix archive.install hex phx_new
mix phx.new local_cents --no-ecto
```

We are avoiding setting up a default Ecto since we will not be using a Postgres database. We will likely re-add Ecto in the future for schema validation.
