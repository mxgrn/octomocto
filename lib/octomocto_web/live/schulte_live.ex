defmodule OctomoctoWeb.SchulteLive do
  use OctomoctoWeb, :live_view

  import OctomoctoWeb.SchulteHTML
  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Schulte}
  alias Octomocto.Schulte.{Game, Store}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))}
  end

  @doc "The title and the description of the Schulte pages, for search engines."
  def seo do
    [
      page_title: "Schulte Table Race: Find Numbers 1–90",
      page_description:
        "Train your focus and speed with a Schulte table. Find the numbers from 1 to 90 in order, alone or in a race with up to 3 friends. Free, in your browser."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"type" => settings.board, "mode" => settings.mode, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       leaderboard: Schulte.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  def handle_event("new_game", _params, socket) do
    %{board: board, mode: mode, players: players, public: public} = socket.assigns.settings
    # Not String.to_existing_atom/1: in dev, the atom can be missing until
    # the Schulte.Game module is loaded
    layout = if board == "random", do: :random, else: :classic
    mode = if mode == "normal", do: :normal, else: :easy
    id = Schulte.create_game(layout, mode, players, public)
    {:noreply, redirect(socket, to: ~p"/schulte/#{id}")}
  end

  # The classic board in the easy mode for one player, and a public game,
  # when the params do not say otherwise
  defp settings(params) do
    board = if params["board"] == "random", do: "random", else: "classic"
    mode = if params["mode"] == "normal", do: "normal", else: "easy"

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    public = params["visibility"] != "private"

    %{board: board, mode: mode, players: players, public: public}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Schulte.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "The board has the numbers from 1 to 90 in a random order.",
      "Click the numbers in order: 1, 2, 3 and so on.",
      "With other players, all players look for the same next number. The first player to click it gets the point. The player with the most points wins.",
      "Alone, find all numbers as fast as you can.",
      "The race starts after a countdown, when all players are in.",
      "In the easy mode, the found numbers disappear. In the normal mode, they stay on the board.",
      "The classic board always has the same shapes. The random board has new shapes for each race."
    ]
  end

  # A small copy of the badge of the page, for a row of the lists
  defp lobby_icon(assigns) do
    ~H"""
    <div class="grid size-9 shrink-0 place-items-center rounded-xl bg-octo-indigo/10 text-[0.6rem] font-bold text-octo-indigo tabular-nums">
      1·2·3
    </div>
    """
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [board: settings.board, mode: settings.mode, players: settings.players]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(%{settings: game_settings} = game, settings) do
    {Atom.to_string(game_settings.layout), Atom.to_string(game_settings.mode),
     game.players_needed} ==
      {settings.board, settings.mode, settings.players}
  end

  @doc "The settings of a game in the list of public games."
  def game_summary(%{settings: settings}) do
    board = if settings.layout == :classic, do: "Classic", else: "Random"
    mode = if settings.mode == :normal, do: "Normal", else: "Easy"
    "#{board} board · #{mode}"
  end
end
