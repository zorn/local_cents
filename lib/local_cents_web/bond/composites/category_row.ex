defmodule LocalCentsWeb.Bond.Composites.CategoryRow do
  @moduledoc """
  A single row in the category management view — one `LocalCents.Tracking.Category`
  in either its display or edit shape.

  In **display** mode the row shows the category `name`, its `count` of filed
  expenses, and pencil/trash affordances that push `on_edit`/`on_delete` (each
  tagged with `category_id`). In **edit** mode — used for both renaming an existing
  category and adding a new one — the name is replaced by a form field with an
  explicit submit (**Create** when adding, **Save** when renaming) and a **✕**
  cancel, following the GitHub inline-edit pattern (no commit-on-blur, so keyboard
  and assistive-tech users act deliberately; Escape also closes the row). The
  edit field autofocuses on mount via a colocated hook; the caller re-keys
  `input_id` to refocus it after a successful add.

  The icon-only buttons carry `sr-only` labels so they are announced by assistive
  tech and matchable by text in tests.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias LocalCentsWeb.Bond
  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :id, :string, required: true, doc: "DOM id for the row's outer element"

  attr :editing, :boolean,
    default: false,
    doc: "When true, render the edit form; otherwise render the display row"

  attr :name, :string, default: nil, doc: "Display mode: the category's name"

  attr :count, :integer,
    default: 0,
    doc: "Display mode: number of expenses filed under the category"

  attr :category_id, :string,
    default: nil,
    doc: "Display mode: the category id sent as phx-value-id with on_edit/on_delete"

  attr :on_edit, :string,
    default: nil,
    doc: "Display mode: event pushed by the pencil (rename) button"

  attr :on_delete, :string,
    default: nil,
    doc: "Display mode: event pushed by the trash (delete) button"

  attr :form, Phoenix.HTML.Form,
    default: nil,
    doc: "Edit mode: the form carrying the `:name` field"

  attr :input_id, :string,
    default: nil,
    doc: "Edit mode: DOM id for the name input; re-key it to refocus after a successful add"

  attr :on_save, :string, default: nil, doc: "Edit mode: form submit event"
  attr :on_cancel, :string, default: nil, doc: "Edit mode: event pushed by the ✕ cancel button"

  attr :on_change, :string,
    default: nil,
    doc: "Edit mode: form change event, for live validation (submit still commits)"

  attr :submit_label, :string,
    default: "Save",
    doc:
      ~s|Edit mode: submit button label — "Create" when adding, "Save" when renaming (see docs/ui-language.md)|

  @spec category_row(Socket.assigns()) :: Rendered.t()
  def category_row(%{editing: true} = assigns) do
    assigns = assign(assigns, :name_error, name_error(assigns.form))

    ~H"""
    <%!-- The input, Save, and ✕ share one `items-center` line of constant height so
    the field's text aligns with the button labels; the validation error is a
    separate line below the row, so it never shifts that alignment. The input is
    rendered field-less (name/value/error unpacked here) precisely so its error does
    not live inside the input wrapper and grow the row. --%>
    <.form
      for={@form}
      id={@id}
      phx-submit={@on_save}
      phx-change={@on_change}
      class="w-full px-4 py-2"
    >
      <div class="flex w-full items-center gap-2">
        <label for={@input_id} class="sr-only">Category name</label>
        <Bond.input
          id={@input_id}
          name={@form[:name].name}
          value={@form[:name].value}
          class="flex-1"
          placeholder="Category name"
          phx-hook=".InlineEditKeys"
          data-on-cancel={@on_cancel}
          autocomplete="off"
        />
        <Bond.button type="submit">{@submit_label}</Bond.button>
        <button
          type="button"
          phx-click={@on_cancel}
          aria-label="Cancel"
          class="shrink-0 text-surface-500 hover:text-primary-800 transition-colors"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
          <span class="sr-only">Cancel</span>
        </button>
      </div>
      <p :if={@name_error} class="mt-1 pl-1 text-xs" style="color: var(--color-error-600)">
        {@name_error}
      </p>
    </.form>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".InlineEditKeys">
      export default {
        mounted() {
          this.el.focus()
          // Put the cursor at the end so a rename appends rather than selects.
          const end = this.el.value.length
          this.el.setSelectionRange(end, end)
          // Escape closes the inline add/rename row (the ✕ button's counterpart),
          // matching the deliberate no-blur-commit editing model.
          this._onKeydown = (e) => {
            if (e.key === "Escape") {
              e.preventDefault()
              this.pushEvent(this.el.dataset.onCancel)
            }
          }
          this.el.addEventListener("keydown", this._onKeydown)
        },
        destroyed() {
          this.el.removeEventListener("keydown", this._onKeydown)
        }
      }
    </script>
    """
  end

  def category_row(assigns) do
    ~H"""
    <div id={@id} class="flex w-full items-center gap-4 px-4 py-3">
      <span class="flex-1 text-sm font-medium text-surface-800 truncate">{@name}</span>
      <span class="shrink-0 text-xs tabular-nums text-surface-500">{count_label(@count)}</span>
      <div class="flex items-center gap-1">
        <button
          type="button"
          phx-click={@on_edit}
          phx-value-id={@category_id}
          class="shrink-0 rounded p-1 text-surface-500 hover:text-primary-800 transition-colors cursor-pointer"
        >
          <.icon name="hero-pencil" class="w-4 h-4" />
          <span class="sr-only">Rename {@name}</span>
        </button>
        <button
          type="button"
          phx-click={@on_delete}
          phx-value-id={@category_id}
          class="shrink-0 rounded p-1 text-surface-500 hover:text-error-600 transition-colors cursor-pointer"
        >
          <.icon name="hero-trash" class="w-4 h-4" />
          <span class="sr-only">Delete {@name}</span>
        </button>
      </div>
    </div>
    """
  end

  # The expense tally as user-facing text. Zero reads as an honest "None" rather
  # than "0 expenses"; one is singular.
  defp count_label(0), do: "No expenses"
  defp count_label(1), do: "1 expense"
  defp count_label(count), do: "#{count} expenses"

  # The first validation error for the name, gated on interaction like
  # `Bond.Elements.Input` does — a pristine required field shows no error. Rendered
  # below the row (not inside the input) to keep the edit line's height constant.
  defp name_error(form) do
    field = form[:name]

    if Phoenix.Component.used_input?(field) do
      field.errors |> List.first() |> translate_error()
    end
  end

  defp translate_error(nil), do: nil

  defp translate_error({msg, opts}) do
    case opts[:count] do
      nil -> Gettext.dgettext(LocalCentsWeb.Gettext, "errors", msg, opts)
      count -> Gettext.dngettext(LocalCentsWeb.Gettext, "errors", msg, msg, count, opts)
    end
  end
end
