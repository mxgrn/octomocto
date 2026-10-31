defmodule OctomoctoWeb.Router do
  use OctomoctoWeb, :router

  import OctomoctoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug OctomoctoWeb.DropInvalidReloadStatus
    plug :fetch_live_flash
    plug :put_root_layout, html: {OctomoctoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug OctomoctoWeb.GuestName
    plug OctomoctoWeb.Locale, "en"
  end

  pipeline :portuguese do
    plug OctomoctoWeb.Locale, "pt"
  end

  pipeline :german do
    plug OctomoctoWeb.Locale, "de"
  end

  pipeline :russian do
    plug OctomoctoWeb.Locale, "ru"
  end

  pipeline :french do
    plug OctomoctoWeb.Locale, "fr"
  end

  pipeline :ukrainian do
    plug OctomoctoWeb.Locale, "uk"
  end

  pipeline :polish do
    plug OctomoctoWeb.Locale, "pl"
  end

  pipeline :italian do
    plug OctomoctoWeb.Locale, "it"
  end

  pipeline :spanish do
    plug OctomoctoWeb.Locale, "es"
  end

  pipeline :japanese do
    plug OctomoctoWeb.Locale, "ja"
  end

  pipeline :vietnamese do
    plug OctomoctoWeb.Locale, "vi"
  end

  pipeline :turkish do
    plug OctomoctoWeb.Locale, "tr"
  end

  pipeline :arabic do
    plug OctomoctoWeb.Locale, "ar"
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OctomoctoWeb do
    pipe_through :browser

    get "/privacy", PageController, :privacy
    get "/terms", PageController, :terms
    get "/astronaut", AstronautController, :index
    post "/astronaut", AstronautController, :create
    get "/astronaut/:id", AstronautController, :show
    get "/schulte/:id", SchulteController, :show
    get "/set/:id", SetGameController, :show
    get "/sudoku/:id", SudokuController, :show
    get "/echo/:id", EchoController, :show
    get "/mahjong/:id", MahjongController, :show
    get "/overlap/:id", OverlapController, :show
    get "/snap/:id", SnapController, :show

    # The front page updates its list of public games live. The
    # settings of a new game: a LiveView changes the settings without a page
    # load, so the page does not scroll to the top on each click.
    live_session :default,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "en"}
      ] do
      live "/", HomeLive
      live "/trains", TrainsLive, :index
      live "/trains/campaign", TrainsLive, :campaign
      live "/trains/lobby", TrainsLive, :lobby
      live "/schulte", SchulteLive
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
      live "/set", SetGameLive
      live "/sudoku", SudokuLive
      live "/echo", EchoLive
      live "/mahjong", MahjongLive
      live "/overlap", OverlapLive
      live "/snap", SnapLive
      live "/stats", StatsLive
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show
    get "/trains/:id", TrainsController, :show
  end

  # The pages in Portuguese, in the same pipeline as the English pages. Only
  # the games with translations are here (see `OctomoctoWeb.Locale`). The
  # other URLs with the prefix go to the English pages.
  scope "/pt", OctomoctoWeb do
    pipe_through [:browser, :portuguese]

    live_session :portuguese,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "pt"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
      live "/echo", EchoLive
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show
    get "/echo/:id", EchoController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in German, the same as the pages in Portuguese
  scope "/de", OctomoctoWeb do
    pipe_through [:browser, :german]

    live_session :german,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "de"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Russian, the same as the pages in Portuguese
  scope "/ru", OctomoctoWeb do
    pipe_through [:browser, :russian]

    live_session :russian,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "ru"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in French, the same as the pages in Portuguese
  scope "/fr", OctomoctoWeb do
    pipe_through [:browser, :french]

    live_session :french,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "fr"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Ukrainian, the same as the pages in Portuguese
  scope "/uk", OctomoctoWeb do
    pipe_through [:browser, :ukrainian]

    live_session :ukrainian,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "uk"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Polish, the same as the pages in Portuguese
  scope "/pl", OctomoctoWeb do
    pipe_through [:browser, :polish]

    live_session :polish,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "pl"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Italian, the same as the pages in Portuguese
  scope "/it", OctomoctoWeb do
    pipe_through [:browser, :italian]

    live_session :italian,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "it"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Spanish, the same as the pages in Portuguese
  scope "/es", OctomoctoWeb do
    pipe_through [:browser, :spanish]

    live_session :spanish,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "es"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Japanese, the same as the pages in Portuguese
  scope "/ja", OctomoctoWeb do
    pipe_through [:browser, :japanese]

    live_session :japanese,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "ja"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Vietnamese, the same as the pages in Portuguese
  scope "/vi", OctomoctoWeb do
    pipe_through [:browser, :vietnamese]

    live_session :vietnamese,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "vi"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Turkish, the same as the pages in Portuguese
  scope "/tr", OctomoctoWeb do
    pipe_through [:browser, :turkish]

    live_session :turkish,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "tr"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # The pages in Arabic, the same as the pages in Portuguese
  scope "/ar", OctomoctoWeb do
    pipe_through [:browser, :arabic]

    live_session :arabic,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        OctomoctoWeb.GuestName,
        {OctomoctoWeb.Locale, "ar"}
      ] do
      live "/memory", MemoryLive, :index
      live "/memory/campaign", MemoryLive, :campaign
      live "/memory/lobby", MemoryLive, :lobby
    end

    # After the live routes, so that "campaign" is not a game id
    get "/memory/:id", MemoryController, :show

    get "/*path", LocaleController, :english
  end

  # For deploys to check that the app is up
  # Only for admins. All other users, also guests, get a 404 page.
  scope "/admin", OctomoctoWeb.Admin do
    pipe_through [:browser, :require_admin]

    live_session :admin,
      on_mount: [
        {OctomoctoWeb.UserAuth, :mount_current_scope},
        {OctomoctoWeb.UserAuth, :require_admin}
      ] do
      live "/", DashboardLive
      live "/notifications", NotificationsLive
      live "/notifications/new", NotificationFormLive, :new
      live "/notifications/:id/edit", NotificationFormLive, :edit
    end
  end

  scope "/", OctomoctoWeb do
    get "/health", HealthController, :show
  end

  # For search engines. Not in the :browser pipeline, because it accepts only html.
  scope "/", OctomoctoWeb do
    get "/sitemap.xml", SitemapController, :show
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
