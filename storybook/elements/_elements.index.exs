defmodule Storybook.Elements do
  use PhoenixStorybook.Index

  def folder_open?, do: true

  def entry("button"), do: [icon: {:fa, "rectangle-ad", :thin}]
  def entry("input"), do: [icon: {:fa, "rectangle-ad", :thin}]
  def entry("list_view"), do: [icon: {:fa, "rectangle-ad", :thin}]
end
