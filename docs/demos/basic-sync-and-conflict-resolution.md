# LocalCents Demo: Basic Sync and Conflict Resolution

TODO:
- add a license to the repo
- update the README with current state

While I have been been using my blog to [promote slices of work](https://mikezornek.com/posts/2026/7/guarding-against-ai-drift/) from this side project I have yet to do any kind of proper announcement post / video demo. One reason I avoided this was because I felt in the past I would often blog about my plans and feel shame when I did not live up to them. This time I wanted to make sure I reached a meaningful milestone before doing any kind of blog post. With [Phase 2](https://github.com/zorn/local_cents/issues/229) of LocalCents coming to a close it is time to share what I've built.

## Format and Deliverable

Going to do this as a blog post with an accompanying YouTube video. I'll host the same video in my own storage for my personal website but put it on YouTube as well.

The video should be a tight (3-5 minute) demo talking out:

- My interest in local-first software (including a short overview, with links to some of my [deeper blog posts](https://mikezornek.com/posts/2025/2/what-is-local-first-software/) on the topic).
- Explain that I wanted some space to experiment with local-first ideals and specifically the [Automerge](https://automerge.org/) CRDT (Conflict-free replicated data type).
- The app is called LocalCents, a simple expense tracker. It is a proof of concept app, not intended for end users but, to demonstrate some technical approaches. Specifically:
  - This is a Tauri app with an inner Elixir/Phoenix implementation.
  - [Tauri](https://tauri.app/) is a cross platform toolkit written in Rust. It notably relies on the system web rendering tools to present the UI and thus delivers a much smaller binary that Electron. Tauri apps can be built for Mac, Windows, Linux, iOS, and Android. This app is currently only building for Mac.
  - The main app is written in Elixir and Phoenix. This is the toolset I've been working in for the last 9 years or so. It was chosen because part of the idea here is that we would distribute a desktop app bundle but also host a web version of the software as well. My using the same tech in both places we have more consistency and confidence.
  - While the app can be used in isolation, the real power comes from the fact that storage is built using Automerge and the demo will showcase that working and how conflicts are handled.
- The Live Demo
  - We have two isolated instances of the app running. One is the Mac client and one is a web client.
  - Both clients have their own copy of the Automerge document.
  - As you make edits, they are first saved in the local storage for that client and then sent as changes across a websocket. As the second peer client sees changes those are applied to the Automerge document and resolved.
  - Do simple edits on both sides.
  - Now the real power of Automerge is that it enables multiple devices to collaborate offline with no central server. The demo we are showing today is just two devices but this algorithm scales to multiple devices with deterministic syncing resolution across many peers at different points in time.
  - So happy path edits are fine and good but one of the things I was interested in exploring is how do you empower the user to understand what is going on behind the scenes. Automerge will always pick a winner during a conflict. In a simple sense it is "newest" wins but internally there is the concept of an operation_id (counter, actor) which is a kind of [Lamport clock](https://en.wikipedia.org/wiki/Lamport_timestamp) allow for deterministic outcomes. When winners are chosen the losing values continue to live on in the document until a new write for that field is recorded. LocalCents uses that knowledge to inform the user about conflicts.
  - Go offline; edit an expense in both instances and then go online; Notice a winner was chosen and the user is inform of the conflict via the bell. They can dismiss the notice or choose an alternate winner.
  - Another edge case is deletion. If an offline edit is saved and then when syncing that entity is deleted we also present a notice to let the user know -- and if they so choose restore the entity with their edit.
- The project is open source and you are welcome to check it out in more detail.
- Some things I've learned along the way:
  - Tauri is pretty cool and seems like a nice lean shell to build desktop apps with. It has the same native framework vs non-native web UI issues to consider if you are trying to create a really good platform experience. As an example one I ran into is presenting context menus, and in my current implementation they always live in the html viewport where a more native experience would use system menus. There [are ways to do this](https://v2.tauri.app/learn/window-menu/), it was just not a demo priority so I did not do it.
  - This was the first time I attempted to bundle the BEAM and Elixir/Phoenix into a app/binary. Seemed to work well and was a fair approach for this scenario.
    - This project uses <https://github.com/livebook-dev/elixirkit> but some other options include: 
    - <https://github.com/elixir-desktop/desktop>
    - <https://github.com/burrito-elixir/burrito>
    - <https://github.com/GenericJam/mob>
    - <https://github.com/bartblast/hologram>
  - This was also the first time I really embraced Storyboard and managing an isolated component system. It worked ok, but I would generally recommend extracting components rather than building them out ahead of time especially early in the project.
  - Automerge is very cool, and using Rustler to embedded it in the Elixir app worked well.
  - I used AI a ton in this project. It was a good learning experience, but it did take away my true comprehension for how Automerge works and how Rust works. I knew enough to get the demo to work but fear the loose ends I don't see. As a comparison when I see people using AI to commit to Elixir projects I contribute to, there are tons of norms broken. I wonder how many I am breaking in my work here.
  - What's Next? Not sure just yet. I am contemplating doing a real commercial project around these ideas but need to spend some time doing actual product research before jumping back into the tech.
