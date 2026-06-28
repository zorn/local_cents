defmodule Storybook.Tokens do
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "palette", :light, "psb:mr-1"}
  def folder_name, do: "Tokens"
end
