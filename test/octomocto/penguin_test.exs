defmodule Octomocto.PenguinTest do
  use ExUnit.Case, async: true

  import Octomocto.PenguinHelpers

  alias Octomocto.Penguin
  alias Octomocto.Penguin.{Game, Maze}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!({Game, id})
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id}
  end

  test "join/1 adds a penguin at the start cell", %{id: id} do
    {:ok, player_id, state} = Penguin.join(id)

    assert [%{id: ^player_id, x: 0, y: 0, score: 0}] = state.players
  end

  test "join/1 gives each penguin a different color", %{id: id} do
    {:ok, _, _} = Penguin.join(id)
    {:ok, _, state} = Penguin.join(id)

    assert [%{color: a}, %{color: b}] = state.players
    assert a != b
  end

  test "join/1 fails for an unknown game" do
    assert Penguin.join("unknown") == {:error, :not_found}
  end

  test "move/3 goes through a passage but not through a wall", %{id: id} do
    {:ok, player_id, state} = Penguin.join(id)
    # The start cell is the top-left corner: north is a wall, and east or south is open.
    open = Enum.find([:east, :south], &Maze.can_move?(passages(state), {0, 0}, &1))
    assert_receive {:penguin_state, _}

    Penguin.move(id, player_id, :north)
    assert_receive {:penguin_state, %{players: [%{x: 0, y: 0, facing: :north}]}}

    Penguin.move(id, player_id, open)
    {x, y} = Maze.step({0, 0}, open)
    assert_receive {:penguin_state, %{players: [%{x: ^x, y: ^y, facing: ^open}]}}
  end

  test "the first penguin at the fish wins the round", %{id: id} do
    {:ok, player_id, state} = Penguin.join(id)
    [fish_x, fish_y] = state.fish

    for dir <- path(passages(state), {0, 0}, {fish_x, fish_y}),
        do: Penguin.move(id, player_id, dir)

    assert_receive {:penguin_state, %{winner: ^player_id, players: [%{score: 1}]}}
  end

  test "a penguin leaves when its process stops", %{id: id} do
    {:ok, player_id, _} = Penguin.join(id)
    {:ok, _, _} = Task.async(fn -> Penguin.join(id) end) |> Task.await()

    assert_receive {:penguin_state, %{players: [_]}}
    assert_receive {:penguin_state, %{players: [_, _]}}
    assert_receive {:penguin_state, %{players: [%{id: ^player_id}]}}
  end
end
