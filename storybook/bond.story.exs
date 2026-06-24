defmodule Storybook.AboutBondPage do
  use PhoenixStorybook.Story, :page
  def doc, do: "An overview of the Bond user interface library and its features."

  def render(assigns) do
    ~H"""
    <section class="prose">
      <%!-- TODO: Get Tailwind typography working in here. --%>
      <h1>Welcome to Bond</h1>

      <p>TODO</p>

      <ul>
        <li>explain the goals of this specficially named ui library</li>
        <li>explain how things are organized</li>
      </ul>
    </section>
    """
  end
end
