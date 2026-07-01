defmodule LocalCentsWeb.Bond.Tokens do
  @moduledoc "Design tokens for the Bond UI system."

  @spec color(atom()) :: String.t()
  def color(:accent), do: "#1e40af"
  def color(:accent_dark), do: "#1b3a9a"
  def color(:accent_light), do: "#6ca0ea"
  def color(:button_shadow), do: "#1e293b"

  def color(:content), do: "#22335c"
  def color(:content_secondary), do: "#6980b0"
  def color(:content_placeholder), do: "#a0b4d0"

  def color(:border), do: "#a8c0e0"
  def color(:border_subtle), do: "#c3d2f0"
  def color(:surface), do: "#ffffff"
  def color(:surface_sunken), do: "#cce0f5"
  def color(:surface_frosted), do: "#b8d0ee"

  def color(:positive_currency), do: "#3f9d6c"

  def color(:title_bar_background), do: "#1e2d4d"
  def color(:title_bar_border), do: "#0d1a35"

  def color(:mac_os_close), do: "#FF5F57"
  def color(:mac_os_minimize), do: "#FEBC2E"
  def color(:mac_os_maximize), do: "#28C840"
end
