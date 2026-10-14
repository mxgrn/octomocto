defmodule OctomoctoWeb.SudokuLive do
  use OctomoctoWeb, :live_view

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [setting: 1, score_list: 1, player_list: 1, format_time: 1, player_name: 1]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Sudoku}
  alias Octomocto.Sudoku.{Game, Puzzle, Store}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: url(~p"/sudoku"), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))}
  end

  @doc "The title and the description of the sudoku pages, for search engines."
  def seo do
    [
      page_title: "Sudoku Race: Multiplayer Sudoku",
      page_description:
        "Fill the same sudoku with up to 4 friends. The first player to put the correct digit in a cell gets the point. Free, in your browser."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"difficulty" => settings.difficulty, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       leaderboard: Sudoku.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  def handle_event("new_game", _params, socket) do
    id = Sudoku.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/sudoku/#{id}")}
  end

  # One player, an easy puzzle and a public game, when the params do not
  # say otherwise
  defp settings(params) do
    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..5 -> n
        _ -> 1
      end

    difficulty =
      if params["difficulty"] in Puzzle.difficulties(), do: params["difficulty"], else: "easy"

    %{players: players, difficulty: difficulty, public: params["visibility"] != "private"}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Sudoku.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "The grid has 9 rows, 9 columns and 9 boxes of 3 by 3 cells. Put a digit from 1 to 9 in each empty cell.",
      "Each row, each column and each box must have each digit one time.",
      "Click a cell, then click a digit below the grid. You can also type the digit, and move with the arrow keys.",
      "A correct digit stays and gets your color. A wrong digit shakes and changes nothing.",
      "All players fill the same grid. The first player who puts the correct digit in a cell gets the point.",
      "The game ends when all cells are full. Alone, solve the puzzle as fast as you can. With other players, fill the most cells."
    ]
  end

  attr :id, :string, required: true
  attr :patch, :string, required: true
  attr :selected, :boolean, required: true
  slot :inner_block, required: true

  defp option(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@selected && "true"}
      class={[
        "min-w-10 rounded-full px-4 py-1.5 text-sm font-medium transition",
        if(@selected,
          do: "bg-octo-indigo text-white shadow-sm",
          else: "text-base-content/70 hover:bg-base-100 hover:text-base-content"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :class, :string, default: nil

  # A small sudoku grid with some digits, the icon of the game
  defp grid_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 36 36" class={@class} aria-hidden="true">
      <rect
        x="1"
        y="1"
        width="34"
        height="34"
        rx="5"
        class="fill-white stroke-base-content/15"
        stroke-width="1.5"
      />
      <path d="M12.33 3v30M23.67 3v30M3 12.33h30M3 23.67h30" class="stroke-base-content/15" />
      <text
        :for={{x, y, digit} <- [{6.7, 9.6, "5"}, {29.3, 9.6, "3"}, {18, 20.9, "9"}, {6.7, 32.2, "1"}]}
        x={x}
        y={y}
        text-anchor="middle"
        font-size="9"
        font-weight="700"
        class="fill-octo-indigo"
      >
        {digit}
      </text>
    </svg>
    """
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [players: settings.players, difficulty: settings.difficulty]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  defp difficulty_hint(difficulty) do
    "The puzzle starts with #{Puzzle.givens(difficulty)} of 81 digits."
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings) do
    game.players_needed == settings.players and game.settings.difficulty == settings.difficulty
  end

  @doc "The settings of a game in the list of public games."
  def game_summary(game), do: "#{String.capitalize(game.settings.difficulty)} · 9×9"
end
