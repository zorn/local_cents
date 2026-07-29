defmodule LocalCentsWeb.PageControllerTest do
  use LocalCentsWeb.ConnCase, async: true

  test "the root path redirects to the library", ~M{conn} do
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/library"
  end

  test "the redirect is client-agnostic — a browser lands in the same place", ~M{conn} do
    conn = conn |> browser_conn() |> get(~p"/")

    assert redirected_to(conn) == ~p"/library"
  end
end
