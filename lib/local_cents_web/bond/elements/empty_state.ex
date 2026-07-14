defmodule LocalCentsWeb.Bond.Elements.EmptyState do
  @moduledoc """
  A dashed-outline placeholder shown where a list would be, when it is empty.

  A centered `message` naming what's missing, with an optional quieter `hint` line
  pointing at how to add the first item. Callers pass the copy; the component owns
  the look, so empty lists read the same across screens (it factors out the kind of
  ad-hoc "nothing here yet" note screens would otherwise inline by hand).
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :message, :string, required: true, doc: "The primary line naming what is missing"

  attr :hint, :string,
    default: nil,
    doc:
      "Optional quieter second line, e.g. how to add the first item; omit to show only the message"

  attr :rest, :global, doc: "HTML attributes passed through to the wrapper element"

  @spec empty_state(Socket.assigns()) :: Rendered.t()
  def empty_state(assigns) do
    ~H"""
    <div
      class="m-4 rounded-lg border border-dashed border-surface-400 px-6 py-10 text-center"
      {@rest}
    >
      <p class="text-sm font-medium text-surface-700">{@message}</p>
      <p :if={@hint} class="mt-1 text-sm text-surface-500">{@hint}</p>
    </div>
    """
  end
end
