defmodule LocalCentsWeb.Bond.Elements.LoadingState do
  @moduledoc """
  A centered, in-progress placeholder shown where a list would be while its contents
  are being prepared — the busy counterpart to
  `LocalCentsWeb.Bond.Elements.EmptyState`.

  A quietly spinning indicator above a `message` naming what is happening, with an
  optional `hint` line. Callers pass the copy; the component owns the look, so a
  "working on it" moment reads the same wherever it appears (e.g. first-run demo
  seeding). The spin is gated on `motion-safe` so it honors a reduced-motion
  preference, and the wrapper is a polite `status` region so assistive tech
  announces the wait.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :message, :string, required: true, doc: "The primary line naming what is happening"

  attr :hint, :string,
    default: nil,
    doc:
      "Optional quieter second line, e.g. reassurance about the wait; omit to show only the message"

  attr :rest, :global, doc: "HTML attributes passed through to the wrapper element"

  @spec loading_state(Socket.assigns()) :: Rendered.t()
  def loading_state(assigns) do
    ~H"""
    <div
      class="m-4 flex flex-col items-center gap-3 rounded-lg px-6 py-12 text-center"
      role="status"
      aria-live="polite"
      {@rest}
    >
      <.icon name="hero-arrow-path" class="size-6 text-surface-500 motion-safe:animate-spin" />
      <div>
        <p class="text-sm font-medium text-surface-700">{@message}</p>
        <p :if={@hint} class="mt-1 text-sm text-surface-500">{@hint}</p>
      </div>
    </div>
    """
  end
end
