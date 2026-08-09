# credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
# The router is a table, not a design: it names every module the app routes to, so its
# dependency count tracks how many screens exist rather than how tangled anything is.
# Same reasoning as the `LocalCentsWeb.Bond` delegation hub, which carries this for the
# same reason. Added deliberately when `/dev/docs` took the router past `max_deps: 15`,
# in preference to raising the ceiling globally and weakening the check everywhere —
# a net-new skip of the kind issue #175 wants made an explicit, reviewable decision.
defmodule LocalCentsWeb.Router do
  use LocalCentsWeb, :router
  import PhoenixStorybook.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug LocalCentsWeb.Plugs.Client
    plug :fetch_live_flash
    plug :put_root_layout, html: {LocalCentsWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => LocalCentsWeb.Plugs.ContentSecurityPolicy.fallback_csp()
    }

    plug LocalCentsWeb.Plugs.ContentSecurityPolicy
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    storybook_assets()
  end

  scope "/", LocalCentsWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/library", LibraryLive

    live_session :book_window do
      live "/books/:book_id", BookLive
      live "/books/:book_id/categories", BookCategoriesLive
      live "/books/:book_id/report", BookReportLive
    end

    live_storybook("/storybook", backend_module: LocalCentsWeb.Storybook)
  end

  # Other scopes may use custom stacks.
  # scope "/api", LocalCentsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:local_cents, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LocalCentsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      # The debug bar's Docs link goes here rather than straight at `/doc/index.html`,
      # so missing or stale docs can offer to rebuild themselves (see ADR 0023).
      live "/docs", LocalCentsWeb.DevDocsLive

      # THROWAWAY prototype for issue #220 — the Automerge conflict experience.
      # Delete once the direction is settled.
      live "/conflict-prototype", LocalCentsWeb.ConflictPrototypeLive
    end
  end
end
