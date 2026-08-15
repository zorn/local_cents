defmodule LocalCentsWeb.DevDocsLive do
  @moduledoc """
  The debug bar's **Docs** destination, mounted at `/dev/docs` in development.

  A gateway in front of the generated docs rather than a link straight at them. `doc/` is
  a gitignored build artifact, so the honest answers to "show me the docs" are three, not
  one: they are current, they are behind the source, or they were never built (see
  [ADR 0023](0023-browser-as-a-second-client.html)). Current is much the commonest, so
  that case redirects straight through and costs nothing — this page only appears when
  there is something worth saying, and then it says it with the button that fixes it.

  Generation runs off the LiveView process via `start_async/3`: `mix docs` takes seconds,
  and blocking the mount would leave the tab blank for all of them.

  Development only — routed inside the `:dev_routes` scope. Because a fresh generation
  redirects into the docs, the panel is unreachable once they are current, which is the
  intent: there is nothing to rebuild.
  """
  use LocalCentsWeb, :live_view

  alias LocalCentsWeb.DevDocs

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    case DevDocs.status() do
      # Nothing to report — go where the user was actually headed.
      {:fresh, _generated_at} ->
        socket |> redirect(to: DevDocs.index_path()) |> ok()

      status ->
        socket
        |> assign(status: status, generating: false, error: nil)
        |> put_title("Docs")
        |> ok()
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} client={@client} window_title={@page_title}>
      <div class="flex h-full flex-col items-center justify-center gap-6 p-8">
        <div class="max-w-md text-center">
          <h1 class="text-lg font-semibold text-surface-800">
            {headline(@status)}
          </h1>
          <p class="mt-2 text-sm text-surface-600">
            {explanation(@status)}
          </p>
        </div>

        <div class="flex flex-col items-center gap-3">
          <Bond.button phx-click="generate" disabled={@generating}>
            {if @generating, do: "Generating…", else: generate_label(@status)}
          </Bond.button>

          <%!-- Stale docs still read fine, so offer them; missing ones cannot be. A plain
          link rather than a second button — rebuilding is the action being urged. --%>
          <.link
            :if={match?({:stale, _generated_at, _changed}, @status)}
            href={DevDocs.index_path()}
            class="text-sm text-surface-600 underline transition-colors hover:text-primary-800"
          >
            Open them as they are
          </.link>
        </div>

        <%!-- `mix docs` runs with `--warnings-as-errors` in precommit but not here, so a
        failure is usually a genuine compile error worth reading in full. --%>
        <pre
          :if={@error}
          class="max-h-64 w-full max-w-2xl overflow-auto rounded bg-surface-900 p-4 text-xs text-white/90"
        ><code>{@error}</code></pre>
      </div>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("generate", _params, socket) do
    socket
    |> assign(generating: true, error: nil)
    |> start_async(:generate, &DevDocs.generate/0)
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:generate, {:ok, {:ok, _output}}, socket) do
    # Straight into the docs the user asked for, rather than back to a page whose only
    # remaining purpose is a link.
    socket |> redirect(to: DevDocs.index_path()) |> noreply()
  end

  def handle_async(:generate, {:ok, {:error, output}}, socket) do
    socket |> assign(generating: false, error: output) |> noreply()
  end

  def handle_async(:generate, {:exit, reason}, socket) do
    socket
    |> assign(generating: false, error: "The docs task could not run: #{inspect(reason)}")
    |> noreply()
  end

  defp headline(:missing), do: "The docs haven't been generated yet"
  defp headline({:stale, _generated_at, _changed}), do: "The docs are out of date"

  defp explanation(:missing) do
    "The doc directory is a build artifact and isn't checked in, so a fresh clone has " <>
      "none until they're built."
  end

  defp explanation({:stale, generated_at, changed}) do
    "Last generated #{format_time(generated_at)}. #{file_count(changed)} changed since."
  end

  defp generate_label(:missing), do: "Generate docs"
  defp generate_label({:stale, _generated_at, _changed}), do: "Regenerate docs"

  defp file_count([_one]), do: "1 source file has"
  defp file_count(changed), do: "#{length(changed)} source files have"

  defp format_time(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")
end
