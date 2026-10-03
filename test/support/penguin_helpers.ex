defmodule Octomocto.PenguinHelpers do
  @moduledoc """
  Helpers to read the public penguin game state in tests.
  """

  alias Octomocto.Penguin.Maze

  def passages(%{passages: passages}) do
    MapSet.new(passages, fn [x1, y1, x2, y2] -> {{x1, y1}, {x2, y2}} end)
  end

  @doc "Directions of the only path from `from` to `to` (breadth-first search)."
  def path(passages, from, to), do: bfs(passages, to, [{from, []}], MapSet.new([from]))

  defp bfs(_passages, to, [{to, dirs} | _], _seen), do: Enum.reverse(dirs)

  defp bfs(passages, to, [{cell, dirs} | queue], seen) do
    next =
      for dir <- Maze.dirs(),
          Maze.can_move?(passages, cell, dir),
          next_cell = Maze.step(cell, dir),
          not MapSet.member?(seen, next_cell),
          do: {next_cell, [dir | dirs]}

    bfs(passages, to, queue ++ next, MapSet.union(seen, MapSet.new(next, &elem(&1, 0))))
  end
end
