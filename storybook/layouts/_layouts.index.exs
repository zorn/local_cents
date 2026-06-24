defmodule Storybook.Layouts do
  use PhoenixStorybook.Index

  def folder_open?, do: true

  def entry("desktop_window"), do: [icon: {:fa, "rectangle-ad", :thin}]
end
