defmodule Octomocto.Graze.WorldTest do
  use ExUnit.Case, async: true

  alias Octomocto.Graze.World

  # A square that stays at `x`, `y`
  defp square(kind, x, y) do
    %{id: -1, kind: kind, size: 28, x: x, y: y, vx: 0.0, vy: 0.0, t: 0, until: 60_000}
  end

  test "hit/4 prefers a danger square to a food square" do
    squares = [square(:food, 510, 500), square(:danger, 490, 500)]
    t = 1000

    assert %{kind: :danger} = World.hit(squares, 500, 500, t)
    assert World.hit(squares, 900, 900, t) == nil
  end

  test "a moving square is at its place of the time" do
    square = %{x: 0.0, y: 100.0, vx: 200.0, vy: -50.0, t: 1000}

    assert World.position(square, 3000) == {400.0, 0.0}
  end

  test "the energy goes down after the start, and food gives some back" do
    player = %{energy: 1.0, energy_at: 0}

    assert World.energy(player, 5000, 0) < 1.0
    assert World.energy(player, 20_000, 0) == 0.0

    fed = World.eat(player, 5000, 0)
    assert fed.energy > World.energy(player, 5000, 0)
    assert fed.energy_at == 5000
  end

  test "limit_move/3 keeps the circle in the field and stops a jump" do
    assert World.limit_move({500, 500}, {-50, 500}, 1000) == {22, 500}

    {x, 500.0} = World.limit_move({100, 500}, {900, 500}, 10)
    assert x < 300
  end

  test "spawn/4 gives squares that fly only vertically or horizontally" do
    for _ <- 1..50 do
      %{vx: vx, vy: vy} = World.spawn(:danger, 1, 0, 0)
      assert vx == 0.0 or vy == 0.0
    end
  end

  test "food squares get faster after the start" do
    speed = fn %{vx: vx, vy: vy} -> abs(vx) + abs(vy) end

    assert speed.(World.spawn(:food, 1, 0, 60)) > speed.(World.spawn(:food, 1, 0, 0))
  end

  test "a perk square is larger and faster than a food square" do
    speed = fn %{vx: vx, vy: vy} -> abs(vx) + abs(vy) end
    average = fn squares -> Enum.sum_by(squares, speed) / length(squares) end

    food = for _ <- 1..100, do: World.spawn(:food, 1, 0, 0)
    perks = for _ <- 1..100, do: World.spawn(:food, 1, 0, 0, perk: :invisible)

    assert %{size: 44, perk: :invisible} = hd(perks)
    assert %{size: 32, perk: nil} = hd(food)
    assert average.(perks) > average.(food)
  end

  test "perk_food?/3 is false while a perk square is in the field" do
    squares = [Map.put(square(:food, 500, 500), :perk, :invisible)]

    refute Enum.any?(1..1000, fn _ -> World.perk_food?(squares, 1000, 0) end)
    assert Enum.any?(1..1000, fn _ -> World.perk_food?([], 1000, 0) end)
  end

  test "perk_food?/3 is false until the pause ends" do
    refute Enum.any?(1..1000, fn _ -> World.perk_food?([], 1000, 1001) end)
  end

  test "hit/5 does not see danger squares for an invisible circle" do
    squares = [square(:danger, 500, 500)]

    assert World.hit(squares, 500, 500, 1000, true) == nil
    assert %{kind: :danger} = World.hit(squares, 500, 500, 1000, false)
  end
end
