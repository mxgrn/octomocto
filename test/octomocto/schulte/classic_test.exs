defmodule Octomocto.Schulte.ClassicTest do
  use ExUnit.Case, async: true

  alias Octomocto.Schulte
  alias Octomocto.Schulte.{Classic, Game}

  test "regions/0 has 90 regions with labels on the board" do
    {width, height} = Classic.size()
    regions = Classic.regions()

    assert length(regions) == 90

    for %{label: [x, y, w, h]} <- regions do
      assert w > 0 and h > 0
      assert x >= 0 and y >= 0 and x + w <= width and y + h <= height
    end
  end

  test "regions/0 shuffles the colors between the shapes that are not cream" do
    cream = "#fbf5e1"
    colors = fn -> Enum.map(Classic.regions(), & &1.color) end
    first = colors.()
    second = colors.()

    assert first != second
    assert Enum.frequencies(first) == Enum.frequencies(second)
    assert Enum.map(first, &(&1 == cream)) == Enum.map(second, &(&1 == cream))
  end

  test "a classic game puts the numbers into the same shapes in a random order" do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!({Game, {id, :classic, 1}})

    {:ok, _player_id, state} = Schulte.join(id)

    assert state.board == Tuple.to_list(Classic.size())
    assert state.min_stretch < 0.3
    assert Enum.map(state.cells, & &1.d) == Enum.map(Classic.regions(), & &1.d)
    assert state.cells |> Enum.map(& &1.number) |> Enum.sort() == Enum.to_list(1..90)
  end
end
