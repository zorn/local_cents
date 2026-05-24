# Command Line History

A place to record generator or other prompts used to create notable files.

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
