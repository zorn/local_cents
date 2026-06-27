defmodule Storybook.Composites do
  use PhoenixStorybook.Index

  def folder_open?, do: true

  def entry("book_cell"), do: [icon: {:fa, "rectangle-ad", :thin}]
end
