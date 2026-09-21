# LocalCents

LocalCents is an open-source research project, a place to tinker and explore [Automerge](https://automerge.org/) and CRDTs. Its domain is an expense-tracking application built for [local-first](https://mikezornek.com/posts/2025/2/what-is-local-first-software/), offline collaboration across multiple devices. The app can currently be run as a desktop application on macOS, but could be expanded to Windows, Linux, and the web in the future.

The initial discovery deliverable on this project is complete. It is [documented on my blog](https://mikezornek.com/posts/2026/8/local-cents/) and tagged as [`v0.1.0-blog-demo`](https://github.com/zorn/local_cents/releases/tag/v0.1.0-blog-demo) in Git.

The rest of the repo is conjecture. I am considering moving forward on a fuller small-business accounting solution, but that is still very much up in the air. I'm doing personal research, interviewing target customers and generally trying to get my head around what I would build if I decided to do so. You will likely continue to see work done on this repo, but it may start to diverge from what I originally delivered in [my demo](https://mikezornek.com/posts/2026/8/local-cents/).

If you are interested in chatting about the project, I'd love to [hear from you](https://mikezornek.com/contact/).

## Project Values

- This project is open source, empowering people to trust the software with their time and data, knowing they will be able to continue to modify and run the software long into the future.
- This project is designed explicitly so that all core features can operate without a centralized server, honoring your privacy without compromising multiple device syncing.

## Tech Stack

Since the goal is a cross-platform binary along with the ability to run the app in a web browser, this application utilizes both the [Tauri](https://tauri.app/) (written in [Rust](https://rust-lang.org/)) and [Phoenix LiveView](https://www.phoenixframework.org/) (written in [Elixir](https://elixir-lang.org/)). The underlying document data format is powered by [Automerge](https://automerge.org/). For more on local-first software and Conflict-free Replicated Data Types, see [What is Local-first Software?](https://mikezornek.com/posts/2025/2/what-is-local-first-software/) on my blog.

## How to launch the project for local development

### Prerequisites

This project uses [asdf](https://asdf-vm.com/) to manage Elixir and Erlang versions. A `.tool-versions` file is included in the repo root with the required versions. With asdf installed, run `asdf install` from the project root to install them.

You will also need [Rust](https://www.rust-lang.org/tools/install) installed, as the project includes a Rust NIF for Automerge integration.

### Setup

Run `mix setup` from the project root folder to download the Elixir dependencies and various asset tooling.

To run the app as a **standard Phoenix application**, from the project root folder:

```bash
iex -S mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

To run the app as a **macOS application bundle**, from the project root folder:

```bash
cargo tauri dev
```

## Release builds

To make a release application bundle, from the project root folder run:

```bash
cargo tauri build
```

Then you can run the following to launch the production bundle with logs going to the console. (Note: This is using Fish-specific syntax if you use a different shell you might need to edit.)

```bash
open -W --stderr (tty) --stdout (tty) tauri/target/release/bundle/macos/local-cents.app
```

This project has not been configured to create notarized / deployable app bundles yet.

## License

LocalCents is released under the [MIT License](https://github.com/zorn/local_cents/blob/main/LICENSE). Copyright (c) 2026 Mike Zornek.
