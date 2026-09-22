defmodule LocalCentsWeb.Bond.Elements.Icon do
  @moduledoc """
  A [Heroicon](https://heroicons.com), rendered as a masked `<span>`.

  The `name` is a Heroicon class such as `"hero-x-mark"`; append `-solid` or
  `-mini` for those styles. Icons are extracted from `deps/heroicons` and bundled
  into `app.css` by the plugin in `assets/vendor/heroicons.js`, so the span carries
  no SVG of its own — the class paints it.

  Size and color come from utility classes on `class`, which defaults to `size-4`.
  It is the shared icon primitive the rest of Bond builds on.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :name, :string, required: true, doc: ~s(The Heroicon class, e.g. "hero-x-mark")

  attr :class, :any, default: "size-4", doc: "Utility classes for size and color"

  @spec icon(Socket.assigns()) :: Rendered.t()
  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end
end
