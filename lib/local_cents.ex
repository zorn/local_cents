defmodule LocalCents do
  @moduledoc """
  The domain root: the namespace under which LocalCents' contexts live.

  LocalCents is a local-first expense tracker. Its business logic is organized
  into contexts under this namespace — today `LocalCents.Tracking`, which owns
  Books and the Expenses inside them. Each context exposes a single public API
  module and keeps its internals private; the web layer and the native shell
  call through those APIs rather than reaching past them (see
  [Module Boundaries](module-boundaries.html)).

  There is no database. A Book's data is an Automerge document persisted as a
  `.lcbook` file (see [ADR 0007](0007-book-runtime-and-persistence.html)); that
  file _is_ the store.
  """

  # The core boundary. Each domain context (e.g. `LocalCents.Tracking`) is its
  # own nested boundary with a distinct public API; this boundary holds the
  # cross-cutting core (Mailer and friends). Contexts are added to `deps` as
  # the core comes to depend on them.
  use Boundary, deps: [], exports: []
end
