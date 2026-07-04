defmodule LocalCents.Tracking.Supervisor do
  @moduledoc """
  Supervises the tracking context's per-Book runtime.

  It owns two children (see [ADR 0007](0007-book-runtime-and-persistence.html)):

    * `LocalCents.Tracking.BookRegistry` — a unique `Registry` mapping a Book id to
      its running `LocalCents.Tracking.BookServer`.
    * `LocalCents.Tracking.BookSupervisor` — a `DynamicSupervisor` under which a
      `BookServer` is started per open Book.

  `LocalCents.Application` starts this single supervisor, keeping the context's
  runtime wiring inside the context boundary rather than spread across the
  application tree.
  """

  use Supervisor

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: LocalCents.Tracking.BookRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: LocalCents.Tracking.BookSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
