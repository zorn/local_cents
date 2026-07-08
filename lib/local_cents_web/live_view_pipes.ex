defmodule LocalCentsWeb.LiveViewPipes do
  @moduledoc """
  Small pipe-friendly wrappers for the tagged tuples LiveView callbacks return.

  `mount/3` must return `{:ok, socket}` and the `handle_*` callbacks
  `{:noreply, socket}`. Wrapping the socket in that tuple with a bare
  `{:ok, socket}` breaks a pipeline: the tuple has to be tacked on at the end,
  so a chain of socket transforms reads inside-out. These helpers are the last
  stage of the pipe instead — `socket |> assign(...) |> ok()` — keeping the
  callback body a single top-to-bottom flow.

  Imported into every LiveView through `LocalCentsWeb.live_view/0`, so the
  functions are available unqualified in any LiveView module.
  """

  alias Phoenix.LiveView.Socket

  @spec ok(Socket.t()) :: {:ok, Socket.t()}
  def ok(%Socket{} = socket), do: {:ok, socket}

  @spec noreply(Socket.t()) :: {:noreply, Socket.t()}
  def noreply(%Socket{} = socket), do: {:noreply, socket}
end
