defmodule LocalCentsWeb.HomeLiveTest do
  use LocalCentsWeb.FeatureCase, async: true

  test "the home page shows a count that starts at zero", ~M{conn} do
    conn
    |> visit(~p"/")
    |> assert_has("span", text: "Count: 0")
  end

  test "clicking the + button increments the count", ~M{conn} do
    conn
    |> visit(~p"/")
    |> click_button("+")
    |> assert_has("span", text: "Count: 1")
  end
end
