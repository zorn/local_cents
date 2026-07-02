defmodule LocalCents do
  @moduledoc """
  LocalCents keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # The core boundary. Each domain context (e.g. `LocalCents.Tracking`) is its
  # own nested boundary with a distinct public API; this boundary holds the
  # cross-cutting core (Mailer and friends). Contexts are added to `deps` as
  # the core comes to depend on them.
  use Boundary, deps: [], exports: []
end
