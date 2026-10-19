defmodule OctomoctoWeb.TrainsLive do
  use OctomoctoWeb, :live_view

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [setting: 1, option: 1, score_list: 1, player_list: 1, player_name: 1]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Trains}
  alias Octomocto.Trains.{Game, Store}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: url(~p"/trains"), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))}
  end

  @doc "The title and the description of the Right on Track pages, for search engines."
  def seo do
    [
      page_title: "Right on Track: Train Switching Puzzle",
      page_description:
        "Click the switches to send each train to the house with its colors. Play solo or with up to 3 friends. Free, in your browser."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)

    filter = %{
      "switch_count" => settings.switch_count,
      "trains_per_house" => settings.trains_per_house,
      "pace" => settings.pace,
      "players" => settings.players
    }

    {:noreply,
     assign(socket,
       settings: settings,
       switch_counts: Trains.switch_counts(settings.players),
       leaderboard: Trains.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  def handle_event("new_game", _params, socket) do
    id = Trains.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/trains/#{id}")}
  end

  # One player, 6 switches, 2 trains for each house, the normal pace and a
  # public game, when the params do not say otherwise. The switches must
  # divide equally between the players.
  defp settings(params) do
    players = int_param(params["players"], 1..4, 1)
    switches = int_param(params["switches"], 1..12, 6)

    %{
      players: players,
      switch_count: Trains.fit_switch_count(switches, players),
      trains_per_house: int_param(params["trains"], 1..7, 2),
      pace: if(params["pace"] in Trains.paces(), do: params["pace"], else: "normal"),
      public: params["visibility"] != "private"
    }
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Trains.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "Trains leave the station one at a time. Each train has the colors of one of the houses.",
      "The tracks split at the switches. Click a switch to change its direction. A train follows the direction of each switch on its way.",
      "Send each train to the house with its colors.",
      "With more players, each player owns some of the switches and can change only those.",
      "The pace tells how fast the trains come one after another.",
      "The round ends when all trains have arrived. The score is the number of trains that got to the correct house."
    ]
  end

  defp int_param(value, range, default) do
    case Integer.parse(value || "") do
      {n, ""} -> if n in range, do: n, else: default
      _ -> default
    end
  end

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state) do
    settings = %{
      players: state.needed,
      switch_count: state.switch_count,
      trains_per_house: state.trains_per_house,
      pace: state.pace,
      public: state.public
    }

    settings_path(settings, %{})
  end

  # The start page with the settings, and with the given changes
  defp settings_path(settings, changes) do
    s = Map.merge(settings, changes)

    query = [
      players: s.players,
      switches: s.switch_count,
      trains: s.trains_per_house,
      pace: s.pace
    ]

    # A public game has no param, so that most links stay short
    query = if s.public, do: query, else: query ++ [visibility: "private"]
    ~p"/trains?#{query}"
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings) do
    game.players_needed == settings.players and
      game.settings.switch_count == settings.switch_count and
      game.settings.trains_per_house == settings.trains_per_house and
      game.settings.pace == settings.pace
  end

  @doc """
  The settings of a game in the list of public games, and the score when
  the round ended.
  """
  def game_summary(%{settings: settings} = game) do
    summary =
      "#{settings.switch_count} switches · #{settings.trains_per_house} per house · #{String.capitalize(settings.pace)}"

    if game[:score], do: summary <> " · " <> format_score(game.score, game.trains), else: summary
  end

  # The number of trains of a round with the settings
  defp trains(settings), do: settings.trains_per_house * (settings.switch_count + 1)

  # For example "92% · 11 of 12"
  defp format_score(score, trains), do: "#{round(score * 100 / trains)}% · #{score} of #{trains}"

  # Tells what a number of switches gives: there is one more house than switches
  defp switches_hint(switches, 1), do: "#{switches + 1} houses."

  defp switches_hint(switches, players) do
    switches_hint(switches, 1) <> " Each player owns #{div(switches, players)} switches."
  end

  defp trains_hint(%{switch_count: switches, trains_per_house: n}),
    do: "#{n * (switches + 1)} trains."

  defp pace_hint("easy"), do: "A train every 8 seconds."

  defp pace_hint("normal"),
    do: "The trains come faster and faster: from 8 down to 2 seconds apart."

  defp pace_hint("hard"), do: "The trains get fast early in the game."
  defp pace_hint("expert"), do: "The trains get very fast very early in the game."
end
