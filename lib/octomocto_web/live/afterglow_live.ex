defmodule OctomoctoWeb.AfterglowLive do
  @moduledoc """
  The settings page of Afterglow, with the lists of public games and the
  results. Alone, the player has no other settings: the page shows the
  tiles of the first round, the tiles of the last round of the last game
  of the user or the guest. With 2 to 4 players, the players take turns
  (see `Octomocto.Afterglow.TurnGame`), and the page has the size of the
  grid and the visibility.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "afterglow"}
  on_mount OctomoctoWeb.BestResults

  import OctomoctoWeb.SettingsComponents,
    only: [
      setting: 1,
      setting_header: 1,
      option: 1,
      score_list: 1,
      player_list: 1,
      result_row: 1,
      result_pill: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Afterglow, Lobby}
  alias Octomocto.Afterglow.{Game, TurnGame, TurnStore, Turns}
  alias OctomoctoWeb.{AfterglowTurnsChannel, MatchPage, SavedSettings}

  def mount(params, session, socket) do
    scope = socket.assigns.current_scope

    # The settings of the next game of a match, see `OctomoctoWeb.MatchPage`
    match = MatchPage.load(params["match"], socket, TurnGame, AfterglowTurnsChannel)
    MatchPage.subscribe(socket, match, TurnGame)

    last_level =
      Afterglow.last_level(
        scope && scope.user.id,
        OctomoctoWeb.GuestName.id_from_session(session)
      )

    level = last_level || Game.min_level()
    side = Game.size(level)

    {:ok,
     socket
     |> assign(
       [
         canonical_url: url(~p"/afterglow"),
         rules: rules(),
         match: match,
         start_level: level,
         first_game: last_level == nil,
         # A small grid with the tiles of the first round, lit at random
         preview: %{side: side, lit: MapSet.new(Enum.take_random(0..(side * side - 1), level))}
       ] ++ seo()
     )
     |> assign_lobby(Lobby.entries(TurnGame, TurnStore))
     |> assign(watchers: Lobby.watchers(TurnGame))}
  end

  @doc "The title and the description of the Afterglow pages, for search engines."
  def seo do
    [
      page_title: "Afterglow Memory: a Memory Matrix-Like Brain Game Online",
      page_description:
        "A free brain game like Memory Matrix from Lumosity: tiles light up for a moment, then click the tiles that were lit. Play alone or with up to 3 friends. No sign-up."
    ]
  end

  # The params of the settings. Without them, the page shows the settings
  # that the user chose last.
  @settings_params ["players", "size", "visibility"]

  def handle_params(params, _uri, socket) do
    match = socket.assigns.match

    settings =
      socket |> settings_params(params, match) |> settings() |> Map.put(:match, match && match.id)

    SavedSettings.save_change(socket, "afterglow", settings, query(%{settings | match: nil}, []))

    {:noreply,
     socket
     |> assign(
       settings: settings,
       user_results: user_results(socket.assigns.current_scope, settings)
     )
     |> OctomoctoWeb.BestResults.assign_best(Afterglow, filter(settings))}
  end

  # A match has its own settings
  defp settings_params(socket, params, nil),
    do: SavedSettings.params(socket, "afterglow", params, @settings_params)

  defp settings_params(_socket, params, %{settings: state} = match),
    do: MatchPage.params(params, match, %{"size" => Integer.to_string(state.size)})

  # The score of the match shows the changes of the players
  def handle_info({:afterglow_turns_state, state}, socket) do
    {:noreply, update(socket, :match, &%{&1 | state: state})}
  end

  # The flash of the pattern on the game page
  def handle_info({:afterglow_turns_flash, _pattern}, socket), do: {:noreply, socket}

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  # A watcher came or left, see `Octomocto.Lobby.watch/3`
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, watchers: Lobby.watchers(TurnGame))}
  end

  @doc """
  Starts a game with turns in the default settings for the number of
  players, and gives its id. See `OctomoctoWeb.NextGame`.
  """
  def create_default_game(players, public) when players > 1 do
    # Any player can start the next game, thus it has no creator (see
    # `Octomocto.Seats`)
    %{settings(%{"players" => Integer.to_string(players)}) | public: public}
    |> Map.put(:creator, false)
    |> Turns.create_game()
  end

  # The next game of the match, in the same game
  def handle_event("new_game", _params, %{assigns: %{match: %{player_id: id} = match}} = socket)
      when is_binary(id) do
    MatchPage.start(TurnGame, match, Map.take(socket.assigns.settings, [:size]))
    {:noreply, redirect(socket, to: ~p"/afterglow/#{match.id}")}
  end

  def handle_event("new_game", _params, %{assigns: %{settings: %{players: 1}}} = socket) do
    id = Afterglow.create_game(%{start_level: socket.assigns.start_level})
    {:noreply, redirect(socket, to: ~p"/afterglow/#{id}")}
  end

  def handle_event("new_game", _params, socket) do
    id = Turns.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/afterglow/#{id}")}
  end

  # One player, and a public game with the smallest grid for the players,
  # when the params do not say otherwise
  defp settings(params) do
    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    size =
      case {players, Integer.parse(params["size"] || "")} do
        {1, _} ->
          nil

        {_, {n, ""}} ->
          if TurnGame.valid_size?(n, players), do: n, else: TurnGame.min_size(players)

        _ ->
          TurnGame.min_size(players)
      end

    %{players: players, size: size, public: params["visibility"] != "private", match: nil}
  end

  # The results that can be compared: all single-player games, or the
  # games with the same number of players and grid
  defp filter(%{players: 1}), do: %{"players" => 1}
  defp filter(settings), do: %{"players" => settings.players, "size" => settings.size}

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, settings),
    do: Afterglow.user_results(scope, filter(settings))

  defp user_results(nil, _settings), do: nil

  defp rules do
    [
      "Some tiles of the grid light up for a moment. Remember where they are.",
      "When the tiles go out, click all tiles that were lit, in any order.",
      "A wrong tile ends the round. After a fully correct round, the next round has one tile more, else it has one tile less. The grid grows with the tiles.",
      "Each correct tile gives points times the number of tiles in the round.",
      "A game has 10 rounds. Your next game starts with the tiles of your last round.",
      "With friends, you take turns and make one pattern together. The first player adds a tile. In your turn, click all tiles of the pattern in any order, then add a new tile.",
      "The pattern does not show again: watch the turns of the others. A wrong tile puts you out. The last player who is in wins.",
      "When half of the grid is in the pattern, all players who are still in share the win.",
      "Afterglow Memory is a Memory Matrix-like game. Lumosity and Memory Matrix are trademarks of Lumos Labs, Inc. Octomocto is not affiliated with Lumos Labs."
    ]
  end

  defp players_hint(1), do: "Each correct round adds a tile."

  defp players_hint(_players),
    do: "Take turns: click the pattern, then add a tile. The game starts when all players are in."

  @doc "The path of this page with the settings of the game with turns in the given state."
  def settings_path(state) do
    settings = %{players: state.needed, size: state.size, public: state.public, match: nil}
    settings_path(settings, [])
  end

  @doc """
  The path of the Change settings button of the game with turns, see
  `OctomoctoWeb.MatchPage.path/2`.
  """
  def match_path(state), do: MatchPage.path(~p"/afterglow", state)

  # The path of this page for the settings, with some of them changed
  defp settings_path(settings, changes), do: ~p"/afterglow?#{query(settings, changes)}"

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [players: settings.players]
    query = if settings.size, do: query ++ [size: settings.size], else: query

    # A public game has no param, so that most links stay short
    query = if settings.public, do: query, else: query ++ [visibility: "private"]
    if settings.match, do: query ++ [match: settings.match], else: query
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings) do
    {game.settings, game.players_needed} == {%{size: settings.size}, settings.players}
  end

  @doc "The settings of a game in the list of public games."
  def game_summary(%{settings: settings}), do: "#{settings.size}×#{settings.size} grid"
end
