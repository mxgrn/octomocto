defmodule Octomocto.AstronautTest do
  use ExUnit.Case, async: true

  import Octomocto.AstronautHelpers

  alias Octomocto.Astronaut
  alias Octomocto.Astronaut.{Game, Maze}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!({Game, id})
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id}
  end

  test "join/1 adds an astronaut at the start cell", %{id: id} do
    {:ok, player_id, state} = Astronaut.join(id)

    assert [%{id: ^player_id, x: 0, y: 0, score: 0}] = state.players
  end

  test "join/1 gives each astronaut a different color", %{id: id} do
    {:ok, _, _} = Astronaut.join(id)
    {:ok, _, state} = Astronaut.join(id)

    assert [%{color: a}, %{color: b}] = state.players
    assert a != b
  end

  test "join/1 fails for an unknown game" do
    assert Astronaut.join("unknown") == {:error, :not_found}
  end

  test "move/3 goes through a passage but not through a wall", %{id: id} do
    {:ok, player_id, state} = Astronaut.join(id)
    # The start cell is the top-left corner: north is a wall, and east or south is open.
    open = Enum.find([:east, :south], &Maze.can_move?(passages(state), {0, 0}, &1))
    assert_receive {:astronaut_state, _}

    Astronaut.move(id, player_id, :north)
    assert_receive {:astronaut_state, %{players: [%{x: 0, y: 0, facing: :north}]}}

    Astronaut.move(id, player_id, open)
    {x, y} = Maze.step({0, 0}, open)
    assert_receive {:astronaut_state, %{players: [%{x: ^x, y: ^y, facing: ^open}]}}
  end

  test "the first astronaut at the pod wins the round", %{id: id} do
    {:ok, player_id, state} = Astronaut.join(id)
    [pod_x, pod_y] = state.pod

    for dir <- path(passages(state), {0, 0}, {pod_x, pod_y}),
        do: Astronaut.move(id, player_id, dir)

    assert_receive {:astronaut_state, %{winner: ^player_id, players: [%{score: 1}]}}
  end

  test "an astronaut leaves when its process stops", %{id: id} do
    {:ok, player_id, _} = Astronaut.join(id)
    {:ok, _, _} = Task.async(fn -> Astronaut.join(id) end) |> Task.await()

    assert_receive {:astronaut_state, %{players: [_]}}
    assert_receive {:astronaut_state, %{players: [_, _]}}
    assert_receive {:astronaut_state, %{players: [%{id: ^player_id}]}}
  end
end
