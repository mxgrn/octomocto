defmodule Octomocto.SchulteTest do
  use ExUnit.Case, async: true

  alias Octomocto.Schulte
  alias Octomocto.Schulte.Game

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!({Game, id})
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id}
  end

  test "join/1 gives a field with each number from 1 to 90 once", %{id: id} do
    {:ok, player_id, state} = Schulte.join(id)

    assert state.cells |> Enum.map(& &1.number) |> Enum.sort() == Enum.to_list(1..90)
    assert state.next == 1
    assert [%{id: ^player_id, score: 0}] = state.players
  end

  test "join/1 fails for an unknown game" do
    assert Schulte.join("unknown") == {:error, :not_found}
  end

  test "pick/3 of the next number gives a point and marks the number", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    Schulte.pick(id, player_id, 1)

    assert_receive {:schulte_state, %{next: 2, players: [%{score: 1}]} = state}
    assert %{found_by: ^player_id} = Enum.find(state.cells, &(&1.number == 1))
  end

  test "pick/3 of a wrong number does nothing", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    Schulte.pick(id, player_id, 2)
    Schulte.pick(id, player_id, 1)

    assert_receive {:schulte_state, %{next: 2, players: [%{score: 1}]}}
  end

  test "only the first player to pick the number gets the point", %{id: id} do
    {:ok, first, _} = Schulte.join(id)
    {:ok, second, _} = Schulte.join(id)

    Schulte.pick(id, first, 1)
    Schulte.pick(id, second, 1)
    Schulte.pick(id, second, 2)

    assert_receive {:schulte_state, %{next: 3, players: [%{score: 1}, %{score: 1}]}}
  end

  test "restart/1 starts a new field with zero scores after all numbers are found", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    for n <- 1..90, do: Schulte.pick(id, player_id, n)
    Schulte.restart(id)

    assert_receive {:schulte_state, %{next: 91, players: [%{score: 90}]}}
    assert_receive {:schulte_state, %{next: 1, players: [%{score: 0}]}}
  end
end
