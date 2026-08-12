defmodule LocalCentsWeb.Sync.Message do
  @moduledoc """
  The wire envelope for one Automerge sync message crossing the peer Channel.

  A sync message is opaque binary (see `LocalCents.Tracking.ExAutomerge`), but a
  Phoenix Channel serializes its payloads as JSON, which cannot carry raw bytes. So
  the two sync peers wrap each message as Base64 text under a `"message"` key, and
  this module owns that one encoding in a single place — `LocalCentsWeb.Sync.Channel`
  (the host) and `LocalCentsWeb.Sync.PeerClient` (the dialer) both use it so they
  cannot drift.
  """

  @doc """
  The Channel topic a peer joins to sync the Book `book_id`, following the project
  topic scheme (`<kind>:<id>`, see [ADR 0011](0011-pubsub-topic-naming.html)).
  """
  @spec topic(book_id :: String.t()) :: String.t()
  def topic(book_id), do: "sync:" <> book_id

  @doc "Wraps a sync message's bytes as the JSON-safe payload pushed over the Channel."
  @spec wrap(sync_message :: binary()) :: %{message: String.t()}
  def wrap(sync_message), do: %{message: Base.encode64(sync_message)}

  @doc "Unwraps a Channel payload back into the sync message's bytes."
  @spec unwrap(payload :: %{String.t() => String.t()}) :: binary()
  def unwrap(%{"message" => encoded}), do: Base.decode64!(encoded)
end
