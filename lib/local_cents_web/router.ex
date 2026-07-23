defmodule LocalCentsWeb.Router do
  use LocalCentsWeb, :router
  import PhoenixStorybook.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
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

    live "/", HomeLive
    live "/library", LibraryLive
    live "/books/:id", BookLive
    live "/books/:book_id/categories", BookCategoriesLive
    live "/books/:book_id/report", BookReportLive

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
    end
  end
end
