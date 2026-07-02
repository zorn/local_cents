defmodule Storybook do
  @moduledoc false

  # phoenix_storybook generates the `Storybook.*` index modules from the files
  # under `storybook/`. They are dev-only presentation scaffolding, not part of
  # our domain, so this boundary claims them (they nest under `Storybook`) and
  # opts out of boundary checks entirely.
  use Boundary, check: [in: false, out: false]
end
