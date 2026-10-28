defmodule Octomocto.SudokuTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  alias Octomocto.Sudoku
  alias Octomocto.Sudoku.{Result, Store}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(sudoku_game(id))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    {:ok, player_id, _} = Sudoku.join(id)
    %{id: id, player_id: player_id}
  end

  # The empty cells, each with its digit in the solution
  defp empty_cells(id) do
    state = Store.read(id)

    for cell <- 0..80,
        elem(state.puzzle, cell) == 0 and not is_map_key(state.filled, cell),
        do: {cell, elem(state.solution, cell)}
  end

  test "a correct digit gets the point, and a wrong digit or a filled cell changes nothing",
       %{id: id, player_id: player_id} do
    [{cell, digit} | _] = empty_cells(id)

    assert Sudoku.place(id, player_id, cell, rem(digit, 9) + 1) == :wrong
    assert Sudoku.place(id, player_id, cell, digit) == :ok
    assert Sudoku.place(id, player_id, cell, digit) == :ignored

    {:ok, nil, state} = Sudoku.watch(id)
    assert %{players: [%{score: 1}], last: %{cell: ^cell}} = state
    assert %{digit: ^digit, player_id: ^player_id} = Enum.at(state.cells, cell)
  end

  test "only a player can place a digit", %{id: id} do
    [{cell, digit} | _] = empty_cells(id)

    assert Sudoku.place(id, "stranger", cell, digit) == :ignored
  end

  test "a full grid finishes the game and saves the result", %{id: id, player_id: player_id} do
    cells = empty_cells(id)

    for {cell, digit} <- cells, do: :ok = Sudoku.place(id, player_id, cell, digit)

    assert {:ok, nil, %{finished: true}} = Sudoku.watch(id)
    assert [%Result{score: score, settings: settings}] = Repo.all(Result)
    assert score == length(cells)
    assert settings == %{"difficulty" => "easy", "players" => 1}
  end

  test "restart starts a new puzzle with zero scores", %{id: id, player_id: player_id} do
    [{cell, digit} | _] = empty_cells(id)
    :ok = Sudoku.place(id, player_id, cell, digit)

    Sudoku.restart(id, player_id)

    assert {:ok, nil, %{players: [%{score: 0}], last: nil}} = Sudoku.watch(id)
    assert Store.read(id).filled == %{}
  end
end
