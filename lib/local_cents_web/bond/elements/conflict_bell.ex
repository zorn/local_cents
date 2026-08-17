defmodule LocalCentsWeb.Bond.Elements.ConflictBell do
  @moduledoc """
  A bell carrying a numbered badge — the ambient signal that synced changes need
  attention.

  It appears in the expenses header only when a sync surfaced a conflict, and the badge
  shows how many. The list of expenses stays clean: this bell, never a per-row marker, is
  the whole signal (see [ADR 0025](0025-two-peer-sync-architecture.html) and the #220
  conflict UX). The button carries an `sr-only` "Synced changes" label so assistive tech —
  and a text-matching test — can name it.

  The button opens the "Synced changes" popup (`LocalCentsWeb.Bond.Composites.SyncedChangesPopup`):
  the caller passes an `id`, the `count`, and the `phx-click` that toggles the popup through
  the `:rest` attributes.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :count, :integer, required: true, doc: "How many synced changes need attention"

  attr :rest, :global,
    doc: "HTML attributes passed through to the button — the caller supplies the `id`"

  @spec conflict_bell(Socket.assigns()) :: Rendered.t()
  def conflict_bell(assigns) do
    ~H"""
    <button
      type="button"
      class="relative inline-flex h-8 w-8 items-center justify-center rounded text-surface-700 hover:bg-surface-50"
      {@rest}
    >
      <.icon name="hero-bell" class="size-5" />
      <span class="absolute -right-1 -top-1 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-error-600 px-1 text-[0.625rem] font-bold leading-none text-white">
        {@count}
      </span>
      <span class="sr-only">Synced changes</span>
    </button>
    """
  end
end
