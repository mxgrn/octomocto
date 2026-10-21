defmodule OctomoctoWeb.OverlapLive do
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "overlap"}

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
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

  alias Octomocto.{Lobby, Overlap}
  alias Octomocto.Overlap.{Game, Store}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: url(~p"/overlap"), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))}
  end

  @doc "The title and the description of the overlap pages, for search engines."
  def seo do
    [
      page_title: "Overlap: a Dobble-Like Game Online",
      page_description:
        "A free game like Dobble or Spot It!: spot the one symbol that two cards share. Play solo against the clock or race up to 3 friends. No sign-up."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"symbols" => 8, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       leaderboard: Overlap.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  @doc """
  Starts a game in the default settings for the number of players, and
  gives its id. See `OctomoctoWeb.NextGame`.
  """
  def create_default_game(players, public) do
    %{settings(%{"players" => Integer.to_string(players)}) | public: public}
    |> Overlap.create_game()
  end

  def handle_event("new_game", _params, socket) do
    id = Overlap.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/overlap/#{id}")}
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
    settings = %{players: state.needed, public: state.public}
    ~p"/overlap?#{query(settings, [])}"
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
