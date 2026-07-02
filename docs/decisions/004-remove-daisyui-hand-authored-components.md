# Remove DaisyUI and Create the Bond Component Library

## Problem Statement

[DaisyUI](https://daisyui.com/) was in this project because it is part of the
default `phx.new` Phoenix installer. DaisyUI supplies a catalog of pre-built
component classes (`btn`, `card`, `modal`, …) and a semantic theming system.

There is nothing wrong with DaisyUI, and this removal decision is not a judgment against
it. The question was whether it fit the *goals of this particular project*.

LocalCents is, at this stage, as much an educational project as a product. A
core aim is to learn — hands-on — what it actually takes to build a component
library well:

- **Handcrafting the components is the point, not a means to an end.** Leaning
  on a ready-made component library would skip past exactly the experience we
  want: designing primitives, naming them, and assembling them into a coherent
  system ourselves.
- **We want to get better with Phoenix Storybook.** Building our own components
  gives us a real catalog to document, organize, and iterate on in storybook,
  rather than documenting someone else's classes.
- **We want to learn accessibility and design tokens from the ground up.**
  Owning the components means owning their markup, focus behavior, and token
  usage — the details you don't engage with when a library handles them for you.

The project guidelines in `CLAUDE.md` reflect this direction: "**Always**
manually write your own tailwind-based components instead of using daisyUI for a
unique, world-class design."

## Decision

Remove DaisyUI and build the UI from hand-authored Tailwind components, collected
in the Bond component library.

The removal ([`254a98e`](254a98e)) deleted both vendored files and stripped the
DaisyUI wiring from `app.css`, `storybook.css`, the layouts, and `home_live.ex`
(~1,340 deletions against ~112 insertions). In its place the styling stack is:

- **Raw Tailwind utilities** for one-off layout, composed into named components
  so templates read as content and intent rather than class soup.
- **Two first-party Tailwind plugins** for the genuinely reusable primitives
  DaisyUI had been covering: `@tailwindcss/typography` (prose) and
  `@tailwindcss/forms`, both added in [`5724adc`](5724adc) and declared via
  `@plugin` in `app.css`. These are low-level utility plugins, not a component
  library, so they don't undercut the learning goal.
- **The Bond component library** as the home for every bespoke component
  (buttons, inputs, panels, list rows, …), documented in Phoenix Storybook.

Because we were no longer using DaisyUI, we needed our own place for reusable
components — so we created **Bond**. The name is a nod to bond paper, and the
design leans into a paper/stationery theme. Bond lives inside the web layer (see
[003](003-bond-namespace-location.md) for where it sits in the module tree). Its
specifics — the component taxonomy, color tokens, and theming — are documented
in the storybook overview and evolve alongside the code, so they are
intentionally not pinned down here.

## Consequences & Tradeoffs

- **We are deliberately taking on work a library would have done for us.** Every
  button, input, and panel is now code we write, style, and maintain. For a
  shipping-velocity-first project that would be a poor trade; for a project whose
  goal is to *learn* component design, accessibility, and storybook, it is the
  whole point.
- **Progress is slower, and that's accepted.** Handcrafting primitives takes
  longer than composing DaisyUI classes. We trade speed for understanding.
- **We own accessibility outright.** Focus states, keyboard interaction, and
  contrast are now our responsibility rather than the library's — which is
  exactly the muscle we want to build, but it means we cannot assume these are
  handled and must verify them ourselves.
- **No semantic component classes exist as a fallback.** New UI must be built
  from Bond components or raw Tailwind; there is no `btn`/`card` shortcut. This
  pushes contributors toward extracting reusable Bond components — the behavior
  we want.
- **This choice is scoped to the project's current educational phase.** If
  priorities shift toward shipping speed later, reaching for a component library
  again would be a reasonable thing to revisit; nothing here is a permanent
  stance against DaisyUI or its peers.
