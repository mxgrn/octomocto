defmodule OctomoctoWeb.Router do
  use OctomoctoWeb, :router

  import OctomoctoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OctomoctoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OctomoctoWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/elm", PageController, :elm
    get "/astronaut", AstronautController, :index
    post "/astronaut", AstronautController, :create
    get "/astronaut/:id", AstronautController, :show
    get "/trains/:id", TrainsController, :show
    get "/schulte/:id", SchulteController, :show
    get "/match/:id", MatchController, :show
    get "/set/:id", SetGameController, :show
    get "/sudoku/:id", SudokuController, :show

    # The settings of a new game. A LiveView changes the settings without a
    # page load, so the page does not scroll to the top on each click.
    live_session :default, on_mount: [{OctomoctoWeb.UserAuth, :mount_current_scope}] do
      live "/trains", TrainsLive
      live "/schulte", SchulteLive
      live "/match", MatchLive
      live "/set", SetGameLive
      live "/sudoku", SudokuLive
    end
  end

  # For deploys to check that the app is up
  scope "/", OctomoctoWeb do
    get "/health", HealthController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", OctomoctoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:octomocto, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OctomoctoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", OctomoctoWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/settings", UserSettingsController, :edit
    put "/settings", UserSettingsController, :update
    get "/settings/confirm-email/:token", UserSettingsController, :confirm_email
    get "/settings/telegram", UserSettingsController, :connect_telegram
  end

  scope "/", OctomoctoWeb do
    pipe_through [:browser]

    get "/signin", UserSessionController, :new
    get "/signin/:token", UserSessionController, :confirm
    post "/signin", UserSessionController, :create
    get "/auth/telegram", UserSessionController, :telegram
    delete "/signout", UserSessionController, :delete
  end
end
