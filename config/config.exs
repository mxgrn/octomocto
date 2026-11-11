# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :octomocto, :scopes,
  user: [
    default: true,
    module: Octomocto.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Octomocto.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :octomocto,
  ecto_repos: [Octomocto.Repo],
  generators: [timestamp_type: :utc_datetime]

# The Mnesia tables that the cluster nodes share
config :mnesiac,
  stores: [
    Octomocto.NimbleMosaic.Store,
    Octomocto.Trains.Store,
    Octomocto.Memory.Store,
    Octomocto.SetGame.Store,
    Octomocto.Sudoku.Store,
    Octomocto.Echo.Store,
    Octomocto.Mahjong.Store,
    Octomocto.Overlap.Store,
    Octomocto.Snap.Store,
    Octomocto.Afterglow.Store,
    Octomocto.Afterglow.TurnStore,
    Octomocto.Schulte.TableStore,
    Octomocto.Graze.Store
  ]

# Configure the endpoint
config :octomocto, OctomoctoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OctomoctoWeb.ErrorHTML, json: OctomoctoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Octomocto.PubSub,
  live_view: [signing_salt: "ZmRD0aYE"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :octomocto, Octomocto.Mailer, adapter: Swoosh.Adapters.Local

# Translates the texts that admins write, such as banners, with an LLM
# (see `Octomocto.Banners.translate/1` and
# `Octomocto.Notifications.translate/1`). The translations are cached in
# the database. The static texts use `OctomoctoWeb.Gettext`.
config :understudy,
  repo: Octomocto.Repo,
  translator:
    {Understudy.Translator.ReqLLM,
     model: "google:gemini-3.1-flash-lite",
     llm_opts: [temperature: 0.5],
     persona:
       "You translate the announcements of Octomocto, a site with free online games to play solo or with friends.",
     style:
       "Informal and friendly. Always use the informal you (du, tu, ты, ти, ty, tu, tú, você).",
     rules: [
       ~s(Never translate "Octomocto".),
       "The text is Markdown. Keep the Markdown syntax, the line breaks and the URLs of the links unchanged.",
       "In French, put a space before ! ? : and ;, but never before a comma or a period, also not after a link."
     ]}

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  octomocto: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  octomocto: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :sentry, before_send: {OctomoctoWeb.SentryFilter, :before_send}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
