defmodule Storybook.Layouts.Modal do
  use LocalCentsWeb.Storybook.Story, :example

  def doc, do: "A centered, dismissible dialog for small focused tasks like rename or delete."

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, open_rename: false, open_delete: false)}
  end

  @impl Phoenix.LiveView
  def handle_event("open_rename", _params, socket),
    do: {:noreply, assign(socket, :open_rename, true)}

  def handle_event("open_delete", _params, socket),
    do: {:noreply, assign(socket, :open_delete, true)}

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, open_rename: false, open_delete: false)}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="font-sans">
      <p class="text-xs text-surface-500 mb-3">
        Backdrop, ×, or Escape dismisses each modal.
      </p>
      <div class="flex gap-2">
        <Bond.button phx-click="open_rename">Rename…</Bond.button>
        <Bond.button variant={:outline} phx-click="open_delete">Delete…</Bond.button>
      </div>

      <Bond.modal :if={@open_rename} id="story-modal-rename" title="Rename Book" on_cancel="close">
        <form phx-submit="close" class="space-y-4">
          <Bond.input label="New name" name="name" value="Family Expenses" class="w-full" />
          <div class="flex items-center justify-end gap-2">
            <Bond.button type="button" variant={:outline} phx-click="close">Cancel</Bond.button>
            <Bond.button type="submit">Rename</Bond.button>
          </div>
        </form>
      </Bond.modal>

      <Bond.modal :if={@open_delete} id="story-modal-delete" title="Delete Book" on_cancel="close">
        <p class="text-sm text-surface-700">
          Delete <span class="font-semibold">Family Expenses</span>? This cannot be undone.
        </p>
        <:actions>
          <Bond.button type="button" variant={:outline} phx-click="close">Cancel</Bond.button>
          <Bond.button type="button" phx-click="close">Delete</Bond.button>
        </:actions>
      </Bond.modal>
    </div>
    """
  end
end
