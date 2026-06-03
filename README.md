# LocalCents

(Brand new project, lots of stuff missing -- but happy to [chat](https://mikezornek.com/contact/) about it.)

LocalCents is an open-source expense-tracking application built for [local-first](https://mikezornek.com/posts/2025/2/what-is-local-first-software/), offline collaboration across multiple devices. The app can be run as a desktop application on macOS, Windows, and Linux, as well as on the web.

## The Job to be Done

Having an accurate, informed understanding of how you and your family spend money empowers you to make thoughtful, long-term decisions that enable a successful, happy life.

To track these expenses reliably, software needs to be readily available and collaborative; this includes support for multiple devices, multiple participants, and offline capabilities.

## Project Values

- This project is open source, empowering people to trust the software with their time and data, knowing they will be able to continue to modify and run the software long into the future.
- This project is designed explicitly so that all core features can operate without a centralized server, honoring your privacy without compromising multiple device syncing.

## About the Developer / Project Goals

Hello! My name is Mike Zornek. I describe myself as both a developer and teacher, and I've been building digital products for over 25 years.

From the suburbs of Philadelphia, I code in [Elixir](https://elixir-lang.org). When I am not coding, I enjoy watching [Phillies](https://www.mlb.com/phillies) baseball and playing video games (mostly laid-back simulations and RPGs).

In addition to providing an end product (which I myself am interested in using), this project is primarily an educational endeavor. It is a space for me to explore and refine my skills with various technologies, some of which I have extensive experience with (Elixir, Phoenix) and others that will be learning opportunities for me (Rust, Automerge).

## AI Disclosure

AI coding is a complex and heavily debated tool for modern developers. For those looking to avoid products and libraries that utilize AI, I want to share a notice here explaining my own use to help people make a more informed decision if they want to use this work.

I do not use AI coding to generate large swaths of code. This is not a vibe-coded project. I tend to use AI to check my work, offer typeahead suggestions (honoring the patterns I've chosen with intent), and explore ideas. At the end of the day, I am responsible for the code I ship.

For more on my thoughts on AI see [my blog](https://mikezornek.com/posts/2026/5/moral-struggles-of-ai-coding/).

## Tech Stack

Since the end goal is a cross-platform binary along with the ability to run the app in a web browser, this application utilizes both the [Tauri](https://tauri.app/) (written in [Rust](https://rust-lang.org/)) and [Phoenix LiveView](https://www.phoenixframework.org/) (written in [Elixir](https://elixir-lang.org/)). The underlying document data format is powered by [Automerge](https://automerge.org/). For more on Local-first software and Conflict-free Replicated Data Types, see [What is Local-first Software?](https://mikezornek.com/posts/2025/2/what-is-local-first-software/) on my blog.

### Phase One Goals

The initial scope of this project is to have a self-contained desktop app running on macOS (with other platforms to follow later) and a mirror of the application running on a web server. We are not building a native mobile app in this first phase, but we will ensure the website functions well within a mobile device's viewport.

Aside: Deploying a [Tauri iOS app](https://tauri.app/start/prerequisites/#ios) requires CocoaPods, and since that is [a dead technology](https://blog.cocoapods.org/CocoaPods-Specs-Repo/), I am not going to use it.

Data synchronization in phase one will have some hard-coded assumptions. We expect a desktop app to be running with a document, the ability to push that document to the web server, and a web version of the app that can edit the document using (mostly) the same UI experience. Automerge will be responsible for keeping the documents in sync and resolving conflicts. When a conflict needs to be manually resolved, the UI will need to address this job to be done, presenting an intuitive, easy-to-use user experience. Designing a good experience here will be one of the main challenges to solve.

The core domain of phase one is expense tracking. I envision the ability to manually create/edit and delete expenses. I'd like to have tags for each so we can group by to totaling, and then some visualization of how money is being spent over time. Longer term, I think there is some value in letting people drag and drop in their credit card statements to do more automated creation and reconciliation, but we will keep things basic to get started. Much later, I could see the app evolving to provide some level of budgeting and goal tracking, but again -- that will come in time.

## How to launch the project for local development

### Prerequisites

This project uses [asdf](https://asdf-vm.com/) to manage Elixir and Erlang versions. A `.tool-versions` file is included in the repo root with the required versions. With asdf installed, run `asdf install` from the project root to install them.

You will also need [Rust](https://www.rust-lang.org/tools/install) installed, as the project includes a Rust NIF for Automerge integration.

### Setup

Run `mix setup` from the project root folder to download the Elixir dependencies and various asset tooling.

To run the app as a **standard Phoenix application** use `mix phx.server` or inside IEx with `iex -S mix phx.server`. Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

To run the app as a **macOS application bundle** use `cargo tauri dev` from the project root folder.

## Release builds 

To make a release application bundle run: `cargo tauri build` from the project root folder.

Then you can run the following to launch the production bundle with logs going to the console. (Note: This is using Fish-specific syntax if you use a different shell you might need to edit.)

```fish
open -W --stderr (tty) --stdout (tty) tauri/target/release/bundle/macos/local-cents.app
```

This project has not been configured to create notarized / deployable app bundles yet.
