defmodule OctomoctoWeb.NimbleMosaicLive do
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, "nimble-mosaic"}
  on_mount OctomoctoWeb.BestResults

  import OctomoctoWeb.SettingsComponents
  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, NimbleMosaic}
  alias OctomoctoWeb.{MatchPage, NimbleMosaicChannel, SavedSettings}
  alias Octomocto.NimbleMosaic.{Game, Store}

  def mount(params, _session, socket) do
    # The settings of the next field of a match, see `OctomoctoWeb.MatchPage`
    match = MatchPage.load(params["match"], socket, Game, NimbleMosaicChannel)
    MatchPage.subscribe(socket, match, Game)

    {:ok,
     socket
     |> assign([canonical_url: canonical_url(socket), rules: rules(), match: match] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  # The Lobby tab has its own URL
  defp canonical_url(%{assigns: %{live_action: :lobby}}), do: url(~p"/nimble-mosaic/lobby")
  defp canonical_url(_socket), do: url(~p"/nimble-mosaic")

  @doc "The title and the description of the Nimble Mosaic pages, for search engines."
  def seo do
    [
      page_title: "Nimble Mosaic: Find the Numbers 1–90 in Order",
      page_description:
        "Train your focus and speed: find the numbers 1 to 90 in order, solo or in a race with up to 3 friends. Free, in your browser."
    ]
  end

  # The params of the settings. Without them, the page shows the settings
  # that the user chose last.
  @settings_params ["board", "mode", "players", "visibility"]

  def handle_params(params, _uri, socket) do
    match = socket.assigns.match

    settings =
      socket |> settings_params(params, match) |> settings() |> Map.put(:match, match && match.id)

    SavedSettings.save_change(
      socket,
      "nimble-mosaic",
      settings,
      query(%{settings | match: nil}, [])
    )

    filter = %{"type" => settings.board, "mode" => settings.mode, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       user_results: user_results(socket.assigns.current_scope, filter)
     )
     |> OctomoctoWeb.BestResults.assign_best(NimbleMosaic, filter)}
  end

  # A match has its own settings
  defp settings_params(socket, params, nil),
    do: SavedSettings.params(socket, "nimble-mosaic", params, @settings_params)

  defp settings_params(_socket, params, %{settings: state} = match),
    do:
      MatchPage.params(params, match, %{
        "board" => Atom.to_string(state.layout),
        "mode" => Atom.to_string(state.mode)
      })

  # The score of the match shows the changes of the players
  def handle_info({:nimble_mosaic_state, state}, socket) do
    {:noreply, update(socket, :match, &%{&1 | state: state})}
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

  # The next field of the match, in the same game
  def handle_event("new_game", _params, %{assigns: %{match: %{player_id: id} = match}} = socket)
      when is_binary(id) do
    settings = socket.assigns.settings

    MatchPage.start(Game, match, %{
      layout: if(settings.board == "random", do: :random, else: :classic),
      mode: if(settings.mode == "normal", do: :normal, else: :easy)
    })

    {:noreply, redirect(socket, to: ~p"/nimble-mosaic/#{match.id}")}
  end

  def handle_event("new_game", _params, socket) do
    id = create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/nimble-mosaic/#{id}")}
  end

  defp create_game(%{board: board, mode: mode, players: players, public: public}, creator \\ true) do
    # Not String.to_existing_atom/1: in dev, the atom can be missing until
    # the NimbleMosaic.Game module is loaded
    layout = if board == "random", do: :random, else: :classic
    mode = if mode == "normal", do: :normal, else: :easy
    NimbleMosaic.create_game(layout, mode, players, public, creator)
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

    %{board: board, mode: mode, players: players, public: public, match: nil}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: NimbleMosaic.user_results(scope, filter)
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

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state) do
    settings = %{
      board: Atom.to_string(state.layout),
      mode: Atom.to_string(state.mode),
      players: state.needed,
      public: state.public,
      match: nil
    }

    ~p"/nimble-mosaic?#{query(settings, [])}"
  end

  @doc "The path of the Change settings button of the game, see `OctomoctoWeb.MatchPage.path/2`."
  def match_path(state), do: MatchPage.path(~p"/nimble-mosaic", state)

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [board: settings.board, mode: settings.mode, players: settings.players]

    # A public game has no param, so that most links stay short
    query = if settings.public, do: query, else: query ++ [visibility: "private"]
    if settings.match, do: query ++ [match: settings.match], else: query
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
