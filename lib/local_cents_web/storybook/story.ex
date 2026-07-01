defmodule LocalCentsWeb.Storybook.Story do
  @moduledoc """
  Thin wrapper around `PhoenixStorybook.Story` that also aliases the Bond
  component library.

  Because every story documents a Bond component, this saves each one from
  repeating `alias LocalCentsWeb.Bond`. Use it exactly like
  `PhoenixStorybook.Story`, passing the story type through:

      use LocalCentsWeb.Storybook.Story, :component

  Stories can then reference `Bond.Elements.Button.button/1`,
  `Bond.Tokens.color/1`, and friends directly.
  """

  defmacro __using__(type) do
    quote do
      use PhoenixStorybook.Story, unquote(type)
      alias LocalCentsWeb.Bond
    end
  end
end
