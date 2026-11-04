defmodule Octomocto.GameProcessTest do
  use ExUnit.Case, async: true

  import Octomocto.GameHelpers

  alias Octomocto.GameProcess
  alias Octomocto.Schulte.{Game, GameSupervisor, Store}

  test "join/9 adds a player to a running game" do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!(schulte_game(id))

    assert {:ok, player_id, %{players: [%{id: player_id}]}} =
             GameProcess.join(Game, Store, GameSupervisor, id, nil, nil, nil, nil, false)
  end

  test "join/9 starts a stopped game again from its copy in the store" do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(schulte_game(id))

    {:ok, _player_id, before} =
      GameProcess.join(Game, Store, GameSupervisor, id, nil, nil, nil, nil, false)

    # As when the node of the game stops
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert {:ok, _player_id, state} =
             GameProcess.join(Game, Store, GameSupervisor, id, nil, nil, nil, nil, false)

    assert state.cells == before.cells
    assert GenServer.whereis(Game.via(id)) not in [nil, pid]
  end

  test "join/9 fails for an unknown game" do
    assert GameProcess.join(Game, Store, GameSupervisor, "unknown", nil, nil, nil, nil, false) ==
             {:error, :not_found}
  end
end
