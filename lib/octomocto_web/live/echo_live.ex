defmodule OctomoctoWeb.EchoLive do
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "echo"}

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SettingsComponents,
    only: [
      setting: 1,
      option: 1,
      score_list: 1,
      player_list: 1,
      result_row: 1,
      result_pill: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Echo, Lobby}
  alias Octomocto.Echo.{Game, Store}

  @default_pads 4

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  @doc "The title and the description of the Echo pages, for search engines."
  def seo do
    [
      page_title: dgettext("echo", "Echo: a Simon-Like Memory Game Online"),
      page_description:
        dgettext(
          "echo",
          "A free game like Simon: repeat the sequence of colored pads. Play alone or with up to 3 friends. No sign-up."
        )
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"pads" => settings.pads, "players" => settings.players}

    locale = socket.assigns.locale

    {:noreply,
     assign(socket,
       settings: settings,
       canonical_url: OctomoctoWeb.Endpoint.url() <> Locale.path(locale, ~p"/echo"),
       alternate_urls: Locale.alternate_urls("echo", ~p"/echo"),
       # The other language keeps the settings
       languages: Locale.languages("echo", locale, ~p"/echo?#{query(settings, [])}"),
       best_results: Echo.best_results(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  # A watcher came or left, see `Octomocto.Lobby.watch/3`
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, watchers: Lobby.watchers(Game))}
  end

  @doc """
  Starts a game in the default settings for the number of players, and
  gives its id. See `OctomoctoWeb.NextGame`.
  """
  def create_default_game(players, public) do
    %{settings(%{"players" => Integer.to_string(players)}) | public: public}
    |> Echo.create_game()
  end

  def handle_event("new_game", _params, socket) do
    id = Echo.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: Locale.path(socket.assigns.locale, ~p"/echo/#{id}"))}
  end

  # 4 pads, one player and a public game, when the params do not say
  # otherwise
  defp settings(params) do
    pads =
      case Integer.parse(params["pads"] || "") do
        {n, ""} when n in 2..8 -> n
        _ -> @default_pads
      end

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    %{pads: pads, players: players, public: params["visibility"] != "private"}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Echo.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      dgettext("echo", "The pads light up one by one. Tap them in the same order."),
      dgettext(
        "echo",
        "Each round, the sequence gets one pad longer. One wrong pad, and the game ends."
      ),
      dgettext(
        "echo",
        "With friends, there is no playback: watch the taps of the others. In your turn, repeat the sequence, then add a pad of your choice."
      ),
      dgettext("echo", "A player who taps a wrong pad is out. The last player who is in wins."),
      dgettext(
        "echo",
        "Echo is a Simon-like game. Simon is a trademark of Hasbro. Octomocto is not affiliated with Hasbro."
      )
    ]
  end

  defp players_hint(1), do: dgettext("echo", "The game adds a random pad each round.")

  defp players_hint(_players),
    do:
      dgettext(
        "echo",
        "Each player repeats the sequence and adds a pad. The game starts when all players are in."
      )

  @doc "The path of this page in the language with the settings of the game in the given state."
  def settings_path(locale, state) do
    settings = %{pads: state.pads, players: state.needed, public: state.public}
    settings_path(locale, settings, [])
  end

  # The path of this page in the language for the settings, with some of them changed
  defp settings_path(locale, settings, changes) do
    Locale.path(locale, ~p"/echo?#{query(settings, changes)}")
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [pads: settings.pads, players: settings.players]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings) do
    {game.settings, game.players_needed} == {%{pads: settings.pads}, settings.players}
  end

  @doc "The settings of a game in the list of public games."
  def game_summary(%{settings: settings}),
    do: dngettext("echo", "%{count} pad", "%{count} pads", settings.pads)
end
