defmodule LocalCentsWeb.Storybook.Story do
  @moduledoc """
  Thin wrapper around `PhoenixStorybook.Story` that also aliases the Bond
  component library.

  Because every story documents a Bond component, this saves each one from
  repeating `alias LocalCentsWeb.Bond`. Use it exactly like
  `PhoenixStorybook.Story`, passing the story type through:

      use LocalCentsWeb.Storybook.Story, :component

  The alias applies to code in the story module body, so `def function`
  and similar can reference `Bond.Elements.Button.button/1` and friends
  directly:

      def function, do: &Bond.Elements.Button.button/1

  It does **not** apply inside variation `slots`/`template` strings. Those
  are compiled by PhoenixStorybook in a separate context that does not see
  the alias, so Bond components used as tags there must be fully qualified:

      slots: ["<LocalCentsWeb.Bond.Elements.Button.button>Save</LocalCentsWeb.Bond.Elements.Button.button>"]

  Writing `<Bond.Elements.Button.button>` in a slot string raises
  `UndefinedFunctionError` at render time.
  """

  defmacro __using__(type) do
    quote do
      use PhoenixStorybook.Story, unquote(type)
      alias LocalCentsWeb.Bond
    end
  end
end
