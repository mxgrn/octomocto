defmodule Octomocto.Astronaut.Maze do
  @moduledoc """
  A square maze of cells `{x, y}`, with `{0, 0}` at the top left and y going
  down (south). The maze is the set of open passages between adjacent cells.
  """

  @type cell :: {non_neg_integer(), non_neg_integer()}
  @type dir :: :north | :east | :south | :west
  @type passage :: {cell(), cell()}

  @dirs [:north, :east, :south, :west]

  def dirs, do: @dirs

  @doc """
  Makes a perfect maze (exactly one path between two cells) with an
  iterative depth-first search ("recursive backtracker").
  """
  @spec generate(pos_integer()) :: MapSet.t(passage())
  def generate(size) do
    carve([{0, 0}], MapSet.new([{0, 0}]), MapSet.new(), size)
  end

  defp carve([], _visited, passages, _size), do: passages

  defp carve([current | rest] = stack, visited, passages, size) do
    case current |> neighbors(size) |> Enum.reject(&MapSet.member?(visited, &1)) do
      [] ->
        carve(rest, visited, passages, size)

      options ->
        next = Enum.random(options)

        carve(
          [next | stack],
          MapSet.put(visited, next),
          MapSet.put(passages, passage(current, next)),
          size
        )
    end
  end

  defp neighbors(cell, size) do
    for dir <- @dirs, {x, y} = step(cell, dir), x in 0..(size - 1), y in 0..(size - 1), do: {x, y}
  end

  @spec can_move?(MapSet.t(passage()), cell(), dir()) :: boolean()
  def can_move?(passages, cell, dir) do
    MapSet.member?(passages, passage(cell, step(cell, dir)))
  end

  @spec step(cell(), dir()) :: {integer(), integer()}
  def step({x, y}, :north), do: {x, y - 1}
  def step({x, y}, :east), do: {x + 1, y}
  def step({x, y}, :south), do: {x, y + 1}
  def step({x, y}, :west), do: {x - 1, y}

  defp passage(a, b) when a < b, do: {a, b}
  defp passage(a, b), do: {b, a}
end
