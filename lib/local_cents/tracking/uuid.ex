defmodule LocalCents.Tracking.UUID do
  @moduledoc """
  Generates random version-4 UUID strings for the tracking context.

  Both Book ids (their `.lcbook` file names) and Expense ids come from here, so
  there is one collision-resistant, filesystem-safe identifier scheme rather than
  two. We generate these ourselves rather than pull in a UUID dependency — the
  value only needs to be unique, not to carry meaning.

  This is a private helper of `LocalCents.Tracking`. Generating a UUID reads the
  system CSPRNG, so it is a side effect that belongs in the process shell; the pure
  functional core (`LocalCents.Tracking.BookDocument`) receives ids as arguments
  rather than calling here (see [ADR 0014](0014-functional-core-process-shell.html)).
  """

  @doc """
  Returns a new, random version-4 UUID string.
  """
  @spec generate() :: String.t()
  def generate do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    # Set the version (4) and variant (RFC 4122) bits.
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    formatted = :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    IO.iodata_to_binary(formatted)
  end
end
