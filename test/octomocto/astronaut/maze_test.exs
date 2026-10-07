defmodule Octomocto.Astronaut.MazeTest do
  use ExUnit.Case, async: true

  alias Octomocto.Astronaut.Maze

  test "generate/1 makes a perfect maze: all cells connected, no loops" do
    size = 9
    passages = Maze.generate(size)

    assert MapSet.size(passages) == size * size - 1
    assert MapSet.size(reachable(passages, [{0, 0}], MapSet.new([{0, 0}]))) == size * size
  end

  defp reachable(_passages, [], seen), do: seen

  defp reachable(passages, [cell | rest], seen) do
    next =
      for dir <- Maze.dirs(),
          Maze.can_move?(passages, cell, dir),
          to = Maze.step(cell, dir),
          not MapSet.member?(seen, to),
          do: to

    reachable(passages, next ++ rest, MapSet.union(seen, MapSet.new(next)))
  end
end
