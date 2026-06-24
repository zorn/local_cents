defmodule Storybook.Bond do
  use PhoenixStorybook.Index

  def folder_open?, do: true

  def entry("button"), do: [icon: {:fa, "rectangle-ad", :thin}]
  def entry("desktop_window"), do: [icon: {:fa, "copy", :thin}]
end
