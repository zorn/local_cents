defmodule Storybook.Root do
  # See https://hexdocs.pm/phoenix_storybook/PhoenixStorybook.Index.html for full index
  # documentation.

  use PhoenixStorybook.Index

  # PhoenixStorybook types entry/1 as `keyword(String.t() | Icon.t())`, which
  # omits `integer()` even though `index:` takes an integer per the library's own
  # docs (and is what pins "overview" to the top of the nav below). Suppress the
  # resulting false-positive callback_type_mismatch from Dialyzer.
  @dialyzer {:nowarn_function, entry: 1}

  def folder_name, do: "Bond"

  def entry("overview"), do: [index: 0]
end
