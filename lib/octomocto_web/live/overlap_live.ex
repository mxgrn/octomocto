defmodule OctomoctoWeb.OverlapLive do
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, "overlap"}
  on_mount OctomoctoWeb.BestResults

  # The same settings and result lists as on the Nimble Mosaic page
  import OctomoctoWeb.SettingsComponents,
    only: [
      setting: 1,
      option: 1,
      setting_header: 1,
      score_list: 1,
      player_list: 1,
      result_row: 1,
      result_pill: 1,
      format_time: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Overlap}
  alias OctomoctoWeb.SavedSettings
  alias Octomocto.Overlap.{Game, Store, Themes}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign(
       [canonical_url: canonical_url(socket), rules: rules(), themes: Themes.list()] ++ seo()
     )
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  # The Lobby tab has its own URL
  defp canonical_url(%{assigns: %{live_action: :lobby}}), do: url(~p"/overlap/lobby")
  defp canonical_url(_socket), do: url(~p"/overlap")

  @doc "The title and the description of the overlap pages, for search engines."
  def seo do
    [
      page_title: "Overlap: a Dobble-Like Game Online",
      page_description:
        "A free game like Dobble or Spot It!: spot the one symbol that two cards share. Play solo against the clock or race up to 3 friends. No sign-up."
    ]
  end

  # The params of the settings. Without them, the page shows the settings
  # that the user chose last.
  @settings_params ["theme", "players", "visibility"]

  def handle_params(params, _uri, socket) do
    settings =
      socket |> SavedSettings.params("overlap", params, @settings_params) |> settings()

    SavedSettings.save_change(socket, "overlap", settings, query(settings, []))

    filter = %{"symbols" => 8, "players" => settings.players}

    # The theme that the Random switch turns back to: the last chosen one,
    # else the default theme
    last_theme =
      cond do
        settings.theme != "random" -> settings.theme
        last = socket.assigns[:last_theme] -> last
        true -> Themes.default()
      end

    {:noreply,
     assign(socket,
       settings: settings,
       last_theme: last_theme,
       user_results: user_results(socket.assigns.current_scope, filter)
     )
     |> OctomoctoWeb.BestResults.assign_best(Overlap, filter)}
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
    # Any player can start the next game, thus it has no creator (see
    # `Octomocto.Seats`)
    %{settings(%{"players" => Integer.to_string(players)}) | public: public}
    |> Map.put(:creator, false)
    |> Overlap.create_game()
  end

  def handle_event("new_game", _params, socket) do
    id = Overlap.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/overlap/#{id}")}
  end

  # The default theme, one player and a public game, when the params do
  # not say otherwise
  defp settings(params) do
    theme =
      if params["theme"] == "random" or Themes.exists?(params["theme"]),
        do: params["theme"],
        else: Themes.default()

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    %{theme: theme, players: players, public: params["visibility"] != "private"}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Overlap.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "The deck has 57 cards with 8 symbols on each card. Any two cards have exactly one symbol in common.",
      "Two cards are on the table. Find their common symbol and click it on one of the cards. The symbols can have different sizes and turns on the two cards.",
      "The card at the right then goes on the pile at the left, and a new card comes from the deck.",
      "A wrong symbol blocks your clicks for 1 second. Do not click at random!",
      "All players look at the same cards. The first player who finds the symbol wins the card.",
      "The game ends when the deck is empty. Alone, clear it as fast as you can. With other players, win the most cards.",
      "The images are Twemoji by Twitter, Inc. and other contributors (CC-BY 4.0).",
      "Overlap is a Dobble-like game. Dobble and Spot It! are trademarks of Asmodee. Octomocto is not affiliated with Asmodee."
    ]
  end

  defp players_hint(1), do: "Clear the deck as fast as you can."

  defp players_hint(_players),
    do: "All players race on the same cards. The game starts when all players are in."

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state) do
    settings = %{theme: Game.theme_choice(state), players: state.needed, public: state.public}
    ~p"/overlap?#{query(settings, [])}"
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [theme: settings.theme, players: settings.players]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game. With the
  # theme "random", any theme is the same.
  defp same_settings?(game, settings) do
    game.players_needed == settings.players and
      settings.theme in ["random", lobby_theme(game).name]
  end

  @doc "The settings of a game in the list of public games: its theme."
  def game_summary(game), do: lobby_theme(game).title

  # The theme of a game in the list of public games. A game from before the
  # themes has no theme in its lobby settings, and a game can have a theme
  # that is not in `Themes` any more. They show the default theme.
  defp lobby_theme(game) do
    Themes.get(game.settings[:theme]) || Themes.get(Themes.default())
  end

  @doc "The path of the cover image of the theme of a game in the list of public games."
  def lobby_cover_path(game), do: game |> lobby_theme() |> cover_path()

  @doc "The path of the cover image of the theme."
  def cover_path(theme) do
    file = "#{theme.cover}.svg"
    ~p"/images/overlap/#{theme.name}/#{file}"
  end
end
