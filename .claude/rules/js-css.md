---
paths:
  - "assets/**"
  - "lib/local_cents_web/**"
  - "storybook/**"
---

# JS and CSS conventions

The Bond component catalog, the Storybook mirroring rule, and the no-npm policy
are in [`CODING_STANDARDS.md`](../../CODING_STANDARDS.md); Bond's own CSS lives in
`lib/local_cents_web/bond/bond.css`.

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/local_cents_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**
