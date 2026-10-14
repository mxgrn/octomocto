defmodule OctomoctoWeb.HomeLive do
  @moduledoc """
  The front page: the list of all games, and the public games of all
  games together (see `Octomocto.Lobby`).
  """
  use OctomoctoWeb, :live_view

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.Lobby

  alias OctomoctoWeb.{GameIcons, MatchLive, SchulteLive, SetGameLive, SudokuLive}

  @games [
    %{
      id: "schulte",
      name: "Schulte Race",
      description:
        "Find the numbers in order. The first player to click the next number gets the point.",
      path: "/schulte",
      icon_class: "bg-octo-indigo/10 dark:bg-octo-indigo-light/15"
    },
    %{
      id: "trains",
      name: "Right on Track",
      description: "Click the switches to send each train to the house with its colors.",
      path: "/trains",
      icon_class: "bg-octo-orange/10 dark:bg-octo-orange-light/15"
    },
    %{
      id: "match",
      name: "Match",
      description:
        "Find the cards with the same image. Play alone against the clock, or take turns.",
      path: "/match",
      icon_class: "bg-sky-500/10 dark:bg-sky-400/15"
    },
    %{
      id: "set",
      name: "Set",
      description:
        "Find 3 cards where each feature is all the same or all different. Race your friends.",
      path: "/set",
      icon_class: "bg-violet-500/10 dark:bg-violet-400/15"
    },
    %{
      id: "sudoku",
      name: "Sudoku Race",
      description:
        "Fill the same sudoku with your friends. The first player to put the correct digit gets the point.",
      path: "/sudoku",
      icon_class: "bg-rose-500/10 dark:bg-rose-400/15"
    },
    %{
      id: "astronaut",
      name: "Station Escape",
      description:
        "Race your friends to the escape pod on a space station that spins while you play.",
      path: "/astronaut",
      icon_class: "bg-octo-navy dark:bg-black/30 dark:ring-1 dark:ring-white/10"
    }
  ]

  # The games that have lists of public games, by the id in
  # @games, with the game module, its store and the page that gives the
  # settings of a game in a row
  @lobbies %{
    "match" => {Octomocto.Match.Game, Octomocto.Match.Store, MatchLive},
    "set" => {Octomocto.SetGame.Game, Octomocto.SetGame.Store, SetGameLive},
    "sudoku" => {Octomocto.Sudoku.Game, Octomocto.Sudoku.Store, SudokuLive},
    "schulte" => {Octomocto.Schulte.Game, Octomocto.Schulte.Store, SchulteLive}
  }

  @kinds_by_game Map.new(@lobbies, fn {kind, {game, _store, _page}} -> {game, kind} end)

  def mount(_params, _session, socket) do
    if connected?(socket) do
      for {_kind, {game, _store, _page}} <- @lobbies, do: Lobby.subscribe(game)
    end

    entries =
      for {kind, {game, store, _page}} <- @lobbies,
          entry <- Lobby.entries(game, store),
          do: Map.put(entry, :kind, kind)

    {:ok,
     socket
     |> assign(games: @games, kinds: Map.new(@games, &{&1.id, &1}))
     |> assign_lobby(entries)}
  end

  def handle_info({:lobby_changed, game, id, entry}, socket) do
    entry = entry && Map.put(entry, :kind, Map.fetch!(@kinds_by_game, game))
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  defp game_path(game), do: "/#{game.kind}/#{game.id}"

  # The settings of a row, as on the settings page of its kind of game
  defp game_summary(game) do
    {_game, _store, page} = Map.fetch!(@lobbies, game.kind)
    page.game_summary(game)
  end

  attr :game, :map, required: true, doc: "an item of @games"
  attr :small, :boolean, default: false, doc: "the size for a row of the lists"

  defp game_icon(assigns) do
    ~H"""
    <div class={[
      "flex shrink-0 items-center justify-center",
      if(@small,
        do: "size-9 rounded-xl",
        else: "size-14 rounded-2xl transition group-hover:scale-105"
      ),
      @game.icon_class
    ]}>
      <GameIcons.game_icon game={@game.id} class={if(@small, do: "size-7", else: "size-10")} />
    </div>
    """
  end
end
