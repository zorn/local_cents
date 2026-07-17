defmodule LocalCentsWeb.LiveViewUnhandledInfo do
  @moduledoc """
  A `@before_compile` hook that appends a catch-all `handle_info/2` to every
  LiveView, logging and ignoring any message no explicit clause matched.

  `LocalCentsWeb.live_view/0` injects this into every `use LocalCentsWeb,
  :live_view`. It exists because of a sharp edge in Phoenix.LiveView.Channel
  (a private LiveView module): a LiveView that defines **no** `handle_info/2` gets
  the framework's own
  log-and-ignore fallback, but defining **any** clause opts out of it and makes the
  view responsible for every message its process receives — an unmatched one raises
  `FunctionClauseError` and crashes the view. Without this hook, each view that
  subscribes to PubSub must hand-write a no-op clause for every signal it does not
  care about, and that boilerplate grows with every new signal type (see
  [ADR 0019](0019-liveview-unhandled-info-fallback.html)).

  Appending the clause *after* the view's own — via `@before_compile` rather than
  inline in the `use` macro — is what keeps a view's specific handlers matching
  first; a catch-all defined early would shadow them. The fallback logs at `:debug`
  so a genuinely forgotten handler still surfaces in development rather than being
  silently swallowed.
  """

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      require Logger

      @impl Phoenix.LiveView
      def handle_info(message, socket) do
        Logger.debug(fn ->
          "#{inspect(__MODULE__)} ignored an unhandled message: #{inspect(message)}"
        end)

        {:noreply, socket}
      end
    end
  end
end
