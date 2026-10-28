defmodule Octomocto.Sudoku.Game do
  @moduledoc """
  One multiplayer sudoku game. All players fill the same grid of 81 cells
  at the same time (see `Octomocto.Sudoku.Puzzle`). The first player who
  puts the correct digit in an empty cell gets one point, and the cell
  shows the color of that player. A wrong digit changes nothing: only the
  player who put it gets `:wrong` back. Nobody sees the grid before the
  countdown is over. The puzzle is finished when all cells are filled.

  The players, the clock, the lists of the settings page and the copy in
  `Octomocto.Sudoku.Store` are the same as in the other games, see
  `Octomocto.RaceServer`. Each change is broadcast on the `"sudoku:<id>"`
  PubSub topic as `{:sudoku_state, state}`.
  """
  use Octomocto.RaceServer,
    topic: "sudoku",
    state_message: :sudoku_state,
    lobby_topic: "sudoku_lobby",
    store: Octomocto.Sudoku.Store,
    context: Octomocto.Sudoku

  alias Octomocto.RaceServer
  alias Octomocto.Sudoku.Puzzle

  @impl true
  def init_settings(%{difficulty: difficulty}) when difficulty in ~w(easy medium hard) do
    %{difficulty: difficulty}
  end

  @impl true
  def new_field(state) do
    {puzzle, solution} = Puzzle.generate(state.difficulty)

    Map.merge(state, %{
      puzzle: puzzle,
      solution: solution,
      # The cells that the players filled, with the player and its color.
      # The color stays when the player leaves.
      filled: %{},
      # The last cell that a player filled
      last: nil
    })
  end

  # Two players can put the correct digit in the same cell at the same
  # time. The first one gets the cell, and the second one is ignored.
  @impl true
  def handle_move({:place, player_id, cell, digit}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil and
             cell in 0..80 and digit in 1..9 do
    cond do
      not RaceServer.started?(state) or not empty?(state, cell) ->
        {:ignore, :ignored, state}

      elem(state.solution, cell) != digit ->
        {:ignore, :wrong, state}

      true ->
        state =
          state
          |> update_in([:players, player_id, :score], &(&1 + 1))
          |> put_in([:filled, cell], %{
            player_id: player_id,
            color: state.players[player_id].color
          })
          |> Map.put(:last, %{player_id: player_id, cell: cell})
          |> finish_when_full()

        {:publish, :ok, state}
    end
  end

  def handle_move({:place, _player_id, _cell, _digit}, state), do: {:ignore, :ignored, state}

  defp empty?(state, cell) do
    elem(state.puzzle, cell) == 0 and not is_map_key(state.filled, cell)
  end

  defp finish_when_full(state) do
    if Enum.any?(0..80, &empty?(state, &1)), do: state, else: RaceServer.finish(state)
  end

  @impl true
  def lobby_settings(state), do: %{difficulty: state.difficulty}

  @impl true
  def result_settings(state), do: %{"difficulty" => state.difficulty}

  # The solution stays on the server, so that nobody can read it in the
  # browser.
  @impl true
  def public_field(state) do
    %{
      # Do not show the grid before the start (also during the countdown),
      # so that nobody can solve it early.
      cells:
        if(RaceServer.started?(state), do: Enum.map(0..80, &public_cell(state, &1)), else: []),
      last: state.last,
      difficulty: state.difficulty
    }
  end

  # Nil for an empty cell. A digit of the puzzle has no player.
  defp public_cell(state, cell) do
    case state.filled do
      %{^cell => filled} ->
        %{digit: elem(state.solution, cell), player_id: filled.player_id, color: filled.color}

      _ ->
        case elem(state.puzzle, cell) do
          0 -> nil
          digit -> %{digit: digit, player_id: nil, color: nil}
        end
    end
  end
end
