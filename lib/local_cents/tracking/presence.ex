defmodule LocalCents.Tracking.Presence do
  @moduledoc """
  Tracks which processes are actively *viewing* an open `Book`, so a
  `LocalCents.Tracking.BookServer` can shut itself down once its last viewer
  disconnects (see [ADR 0007](0007-book-runtime-and-persistence.html)'s lifecycle
  and `docs/book-runtime-lifecycle.md`).

  A "viewer" is a process that called `LocalCents.Tracking.register_viewer/1` — in
  practice a document-window LiveView on connected mount. It is tracked on the
  Book's dedicated `"book_presence:<id>"` topic, distinct from the `"book:<id>"`
  change-broadcast topic. Because tracking lives in this process (a peer of the
  BookServer, not inside it), it **survives a BookServer crash/restart**: the
  restarted server reads `list/1` at `init` and sees the still-open viewers rather
  than reaping out from under them.

  This is deliberately *not* the same thing as a `Phoenix.PubSub` subscriber: the
  library window subscribes to every Book's change topic to keep its "Last Updated"
  subtitles live, but it never *views* those Books, so it must never count toward
  keeping one resident. Subscribing is passive; tracking here is what marks a viewer.

  Callers reach this only through the `LocalCents.Tracking` facade
  (`register_viewer/1`), never directly — the same discipline the PubSub topic
  scheme keeps (see [ADR 0011](0011-pubsub-topic-naming.html)).
  """

  use Phoenix.Presence,
    otp_app: :local_cents,
    pubsub_server: LocalCents.PubSub
end
