# Bond Namespace Location

## Problem Statement

Bond is the LocalCents component library (named after bond paper). It was
originally placed at the top level of the `lib/` tree as `Bond.*`, living in
`lib/bond/`, with its component CSS in `lib/bond/bond.css`.

The motivation for the top-level placement was isolation: treat Bond as its own
boundary so it would not become entangled with any other module tree.

In practice, that boundary did not exist. Bond already depended on the web layer
in both directions:

- **Bond → LocalCentsWeb:** several components (`ActionChip`, `SidePanel`,
  `Input`) `import LocalCentsWeb.CoreComponents, only: [icon: 1]`, and `Input`
  calls `LocalCentsWeb.Gettext` for error translation.
- **LocalCentsWeb → Bond:** LiveViews render `<Bond.…>` components.

Every Bond component is built on `Phoenix.Component`. The result was a
dependency cycle between two sibling top-level namespaces (`Bond ⇄
LocalCentsWeb`) that compiled only because they belong to the same app — a
boundary in name but not in fact.

The CSS was similarly muddled. Bond styles were split arbitrarily between
`lib/bond/bond.css` and `assets/css/app.css`, and `.font-nunito` was duplicated
in both `app.css` and `storybook.css`. Because `storybook.css` is a separate
Tailwind build that does not import `app.css`, several Bond styles defined only
in `app.css` (`.nb-ruled`, `.nb-tex-*`, `.nb-graph`, `.nb-stamp-*`) were
effectively missing from the storybook build.

## Decision

Move Bond inside the web layer: `lib/bond/` → `lib/local_cents_web/bond/`, and
rename all modules `Bond.*` → `LocalCentsWeb.Bond.*`.

Bond is a Phoenix component library for this app and is not intended to be
extracted into a reusable package or shared across other applications. Given
that intent, the existing coupling to `LocalCentsWeb.CoreComponents` and
`LocalCentsWeb.Gettext` is no longer a smell — it is intra-layer, and the honest
home for the code is inside `local_cents_web`, the part of the tree that
represents "things working with Phoenix."

Supporting choices:

- **Facade ergonomics preserved via an app-wide alias.** `alias
  LocalCentsWeb.Bond` was added to the `html_helpers/0` block in
  `local_cents_web.ex`, so templates across all LiveViews keep writing
  `<Bond.button>` exactly as before. Bond source files — which do not `use
  LocalCentsWeb, :html` — carry a per-file `alias LocalCentsWeb.Bond`.
- **Storybook stories alias Bond through a shared wrapper.** Rather than
  repeating `alias LocalCentsWeb.Bond` in every story, stories `use
  LocalCentsWeb.Storybook.Story` — a thin macro that delegates to
  `PhoenixStorybook.Story` and injects the alias. Every story documents a Bond
  component, so the alias belongs in the shared `use`, mirroring the
  `use LocalCentsWeb, :live_view` pattern.
- **CSS consolidated into `bond.css`, kept as a shared partial.** All Bond
  styles (including the ones stranded in `app.css`) now live in
  `lib/local_cents_web/bond/bond.css`. Both `app.css` and `storybook.css`
  import it, and neither redefines Bond styles. The duplicated `.font-nunito`
  was removed from both entry points. `bond.css` was *not* merged into
  `app.css`, because the standalone storybook Tailwind build needs the same
  styles — a shared partial is the correct structure for two consumers.
- **`@source "../../lib/bond"`** was dropped from both `app.css` and
  `storybook.css`; the existing `@source "../../lib/local_cents_web"` now covers
  the relocated tree.
- **The design system keeps the name "Bond."** Only the Elixir module namespace
  changed. Storybook navigation, prose, and doc examples continue to refer to
  "Bond."

## Consequences & Tradeoffs

- We considered keeping Bond top-level and instead making the boundary real —
  severing its dependencies on `LocalCentsWeb` (passing `icon` in as a slot,
  dropping the `Gettext` coupling) so it could one day be extracted as its own
  package. We rejected this because there is no intent to reuse Bond outside this
  app; the extra indirection would be cost without payoff.
- Moving into `local_cents_web` means Bond can never be extracted without a
  rename. That is an accepted, deliberate consequence of the decision above.
- Consolidating the CSS fixed a latent bug: Bond styles that were defined only
  in `app.css` now render correctly in the standalone storybook build.
- At the time of this move, several notebook-texture classes (`.nb-ruled`,
  `.nb-stamp-bloom`, `.nb-stamp-hatch`, `.nb-tex-*`, `.nb-graph`) were unused
  and were carried into `bond.css` as pruning candidates. They have since been
  renamed to the stationery vocabulary (`bond-*`) and the genuinely unused ones
  pruned, so those exact class names no longer exist.
