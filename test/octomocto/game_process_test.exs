defmodule Octomocto.GameProcessTest do
  use ExUnit.Case, async: true

  alias Octomocto.GameProcess
  alias Octomocto.Schulte.{Game, GameSupervisor, Store}

  test "join/7 adds a player to a running game" do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!({Game, {id, :random, :easy, 1}})

    assert {:ok, player_id, %{players: [%{id: player_id}]}} =
             GameProcess.join(Game, Store, GameSupervisor, id, nil, nil, nil)
  end

  test "join/7 starts a stopped game again from its copy in the store" do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!({Game, {id, :random, :easy, 1}})
    {:ok, _player_id, before} = GameProcess.join(Game, Store, GameSupervisor, id, nil, nil, nil)

    # As when the node of the game stops
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert {:ok, _player_id, state} =
             GameProcess.join(Game, Store, GameSupervisor, id, nil, nil, nil)

    assert state.cells == before.cells
    assert GenServer.whereis(Game.via(id)) not in [nil, pid]
  end

  test "join/7 fails for an unknown game" do
    assert GameProcess.join(Game, Store, GameSupervisor, "unknown", nil, nil, nil) ==
             {:error, :not_found}
  end
end
