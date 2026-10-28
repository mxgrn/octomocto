defmodule OctomoctoWeb.MahjongLive do
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "mahjong"}

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SettingsComponents,
    only: [
      setting: 1,
      option: 1,
      score_list: 1,
      player_list: 1,
      result_row: 1,
      result_pill: 1,
      format_time: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Mahjong}
  alias Octomocto.Mahjong.{Game, Store}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: url(~p"/mahjong"), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  @doc "The title and the description of the mahjong pages, for search engines."
  def seo do
    [
      page_title: "Mahjong Solitaire Online: Solo or Multiplayer",
      page_description:
        "Clear the Turtle in mahjong solitaire, alone or with up to 3 friends on the same board. Free, instant, no sign-up."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"layout" => "turtle", "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       best_results: Mahjong.best_results(filter),
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
    |> Mahjong.create_game()
  end

  def handle_event("new_game", _params, socket) do
    id = Mahjong.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/mahjong/#{id}")}
  end

  # One player and a public game, when the params do not say otherwise
  defp settings(params) do
    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    %{players: players, public: params["visibility"] != "private"}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Mahjong.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "The board has 144 tiles in layers. Remove all of them, two at a time.",
      "Click two free tiles with the same picture. A tile is free when no tile lies on it, and its left or its right side is open.",
      "Flowers and card suits are different: any two flowers make a pair, and any two of ♠ ♥ ♦ ♣ make a pair, also when their pictures are different.",
      "When no pair is free, click Shuffle to mix the faces of the tiles that are left.",
      "All players play on the same board. The first player who removes a pair gets the point.",
      "The game ends when the board is empty. Alone, clear it as fast as you can. With other players, remove the most pairs."
    ]
  end

  defp players_hint(1), do: "Clear the board as fast as you can."

  defp players_hint(_players),
    do: "All players race on the same board. The game starts when all players are in."

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state) do
    settings = %{players: state.needed, public: state.public}
    ~p"/mahjong?#{query(settings, [])}"
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [players: settings.players]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings), do: game.players_needed == settings.players

  @doc "The settings of a game in the list of public games: none, because they never change."
  def game_summary(_game), do: nil
end
