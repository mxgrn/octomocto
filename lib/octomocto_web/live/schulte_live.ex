defmodule OctomoctoWeb.SchulteLive do
  @moduledoc """
  The settings page of the classic Schulte tables: the size of the grid,
  the marks on the found numbers, the players and the visibility, with the
  public games and the results of the selected settings.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "schulte"}

  import OctomoctoWeb.SettingsComponents
  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Schulte}
  alias OctomoctoWeb.SavedSettings
  alias Octomocto.Schulte.{Game, TableStore}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: url(~p"/schulte"), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, TableStore))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  @doc "The title and the description of the Schulte pages, for search engines."
  def seo do
    [
      page_title: "Schulte Table Online: Find the Numbers in Order",
      page_description:
        "Classic Schulte tables from 5×5 to 9×9. Find the numbers in order to train focus, peripheral vision and speed reading. Solo or in a race with up to 3 friends. Free, in your browser."
    ]
  end

  # The params of the settings. Without them, the page shows the settings
  # that the user chose last.
  @settings_params ["size", "marks", "players", "visibility"]

  def handle_params(params, _uri, socket) do
    settings =
      socket |> SavedSettings.params("schulte", params, @settings_params) |> settings()

    SavedSettings.save_change(socket, "schulte", settings, query(settings, []))

    filter = %{"size" => settings.size, "marks" => settings.marks, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       best_results: Schulte.best_results(filter),
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
    # Any player can start the next game, thus it has no creator (see
    # `Octomocto.Seats`)
    create_game(%{settings(%{"players" => Integer.to_string(players)}) | public: public}, false)
  end

  def handle_event("new_game", _params, socket) do
    id = create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/schulte/#{id}")}
  end

  defp create_game(%{size: size, marks: marks, players: players, public: public}, creator \\ true) do
    Schulte.create_game(size, marks, players, public, creator)
  end

  # A 5 × 5 grid without marks for one player, and a public game, when the
  # params do not say otherwise
  defp settings(params) do
    size =
      case Integer.parse(params["size"] || "") do
        {n, ""} -> if n in Game.sizes(), do: n, else: 5
        _ -> 5
      end

    marks = params["marks"] == "on"

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    public = params["visibility"] != "private"

    %{size: size, marks: marks, players: players, public: public}
  end

  defp size_hint(size), do: "The numbers from 1 to #{size * size}."

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Schulte.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "The table is a square grid with the numbers from 1 to the number of cells, in a random order. A 5×5 table has the numbers from 1 to 25.",
      "Click the numbers in order: 1, 2, 3 and so on.",
      "Keep your eyes on the dot in the center of the table, and find the numbers with your peripheral vision. Do not move your eyes from cell to cell.",
      "With other players, all players look for the same next number. The first player to click it gets the point. The player with the most points wins.",
      "Alone, find all numbers as fast as you can.",
      "The race starts after a countdown, when all players are in.",
      "Without marks (the classic rule), the found numbers look the same as the other numbers. With marks, the found numbers become pale."
    ]
  end

  # A small copy of the badge of the page, for a row of the lists
  defp lobby_icon(assigns) do
    ~H"""
    <div class="grid size-9 shrink-0 place-items-center rounded-xl bg-octo-indigo/10">
      <OctomoctoWeb.GameIcons.game_icon game="schulte" class="size-6" />
    </div>
    """
  end

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state) do
    settings = %{
      size: state.size,
      marks: state.marks,
      players: state.needed,
      public: state.public
    }

    ~p"/schulte?#{query(settings, [])}"
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    marks = if settings.marks, do: "on", else: "off"
    query = [size: settings.size, marks: marks, players: settings.players]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(%{settings: game_settings} = game, settings) do
    {game_settings.size, game_settings.marks, game.players_needed} ==
      {settings.size, settings.marks, settings.players}
  end

  @doc "The settings of a game in the list of public games."
  def game_summary(%{settings: settings}) do
    marks = if settings.marks, do: "With marks", else: "No marks"
    "#{settings.size}×#{settings.size} · #{marks}"
  end
end
