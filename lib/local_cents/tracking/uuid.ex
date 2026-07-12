defmodule LocalCents.Tracking.UUID do
  @moduledoc """
  Generates random version-4 UUID strings for the tracking context.

  Both Book ids (their `.lcbook` file names) and Expense ids come from here, so
  there is one collision-resistant, filesystem-safe identifier scheme rather than
  two, and one place to swap the implementation.

  Backed by `Ecto.UUID` (a dependency since the `Expense` schema — see
  [ADR 0016](0016-ecto-embedded-validation-no-repo.html)), so we no longer
  hand-roll the bytes. This module stays as the tracking-scoped name so callers do
  not spread a direct `Ecto.UUID` dependency.

  This is a private helper of `LocalCents.Tracking`. Generating a UUID reads the
  system CSPRNG, so it is a side effect that belongs in the process shell; the pure
  functional core (`LocalCents.Tracking.BookDocument`) receives ids as arguments
  rather than calling here (see [ADR 0014](0014-functional-core-process-shell.html)).
  """

  @doc """
  Returns a new, random version-4 UUID string.
  """
  @spec generate() :: String.t()
  def generate, do: Ecto.UUID.generate()
end
