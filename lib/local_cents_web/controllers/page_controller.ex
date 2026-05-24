defmodule LocalCentsWeb.PageController do
  use LocalCentsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
