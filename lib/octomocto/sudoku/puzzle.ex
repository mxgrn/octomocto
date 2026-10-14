defmodule Octomocto.Sudoku.Puzzle do
  @moduledoc """
  Makes sudoku puzzles with exactly one solution. A grid is a tuple of 81
  digits, row by row. A 0 is an empty cell.

  A new puzzle starts as a full random grid. Then the digits go off one by
  one, in a random order. A digit stays when the grid has more than one
  solution without it. The difficulty sets how many digits stay.
  """

  import Bitwise

  @difficulties ~w(easy medium hard)

  # The number of digits that stay on the grid. A grid with fewer digits
  # is harder.
  @givens %{"easy" => 40, "medium" => 32, "hard" => 26}

  # The 20 other cells in the row, the column and the box of each cell
  @peers (for cell <- 0..80 do
            row = div(cell, 9)
            col = rem(cell, 9)
            box = div(row, 3) * 3 * 9 + div(col, 3) * 3

            row_cells = for c <- 0..8, do: row * 9 + c
            col_cells = for r <- 0..8, do: r * 9 + col
            box_cells = for r <- 0..2, c <- 0..2, do: box + r * 9 + c

            Enum.uniq(row_cells ++ col_cells ++ box_cells) -- [cell]
          end)
         |> List.to_tuple()

  def difficulties, do: @difficulties

  @doc "The number of digits that a new puzzle of the difficulty has."
  def givens(difficulty), do: Map.fetch!(@givens, difficulty)

  @doc """
  Gives `{puzzle, solution}` for the difficulty: `"easy"`, `"medium"` or
  `"hard"`.
  """
  def generate(difficulty) when difficulty in @difficulties do
    [solution] = solve(Tuple.duplicate(0, 81), 1, true)
    {remove_digits(solution, @givens[difficulty]), solution}
  end

  @doc "The number of solutions of the grid, but not more than `limit`."
  def count_solutions(grid, limit) do
    grid |> solve(limit, false) |> length()
  end

  # Takes off the digits in a random order while the grid has one solution
  # and more than `givens` digits
  defp remove_digits(grid, givens) do
    Enum.shuffle(0..80)
    |> Enum.reduce_while({grid, 81}, fn cell, {grid, count} ->
      if count == givens do
        {:halt, {grid, count}}
      else
        without = put_elem(grid, cell, 0)

        if count_solutions(without, 2) == 1,
          do: {:cont, {without, count - 1}},
          else: {:cont, {grid, count}}
      end
    end)
    |> elem(0)
  end

  # Gives up to `limit` solutions. Each step fills the empty cell with the
  # fewest candidates. With `shuffle`, the candidates go in a random order,
  # so that the first solution is a random full grid.
  defp solve(grid, limit, shuffle) do
    grid |> solve(limit, shuffle, []) |> Enum.reverse()
  end

  defp solve(grid, limit, shuffle, found) do
    case best_cell(grid) do
      :full ->
        [grid | found]

      :dead_end ->
        found

      {cell, candidates} ->
        candidates = if shuffle, do: Enum.shuffle(candidates), else: candidates

        Enum.reduce_while(candidates, found, fn digit, found ->
          found = solve(put_elem(grid, cell, digit), limit, shuffle, found)
          if length(found) >= limit, do: {:halt, found}, else: {:cont, found}
        end)
    end
  end

  # The empty cell with the fewest candidates, `:full` when no cell is
  # empty, and `:dead_end` when an empty cell has no candidates
  defp best_cell(grid) do
    Enum.reduce_while(0..80, :full, fn cell, best ->
      if elem(grid, cell) == 0 do
        case candidates(grid, cell) do
          [] ->
            {:halt, :dead_end}

          [_] = one ->
            {:halt, {cell, one}}

          many ->
            case best do
              {_cell, current} when length(current) <= length(many) -> {:cont, best}
              _ -> {:cont, {cell, many}}
            end
        end
      else
        {:cont, best}
      end
    end)
  end

  defp candidates(grid, cell) do
    used =
      Enum.reduce(elem(@peers, cell), 0, fn peer, used ->
        used ||| 1 <<< elem(grid, peer)
      end)

    for digit <- 1..9, (used &&& 1 <<< digit) == 0, do: digit
  end
end
