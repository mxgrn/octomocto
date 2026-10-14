defmodule OctomoctoWeb.GameChannelTest do
  # The Schulte channel uses OctomoctoWeb.GameChannel for the join and the
  # rejoin
  use OctomoctoWeb.ChannelCase, async: true

  alias Octomocto.Schulte.Game
  alias OctomoctoWeb.{SchulteChannel, UserSocket}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!({Game, {id, :random, :easy, 2}})
    %{id: id, pid: pid}
  end

  defp join_game(id, params \\ %{}) do
    UserSocket |> socket() |> subscribe_and_join(SchulteChannel, "schulte:" <> id, params)
  end

  test "a join with the token of a player gives the same player", %{id: id} do
    {:ok, %{player_id: player_id, token: token}, _socket} = join_game(id)

    assert {:ok, %{player_id: ^player_id}, _socket} = join_game(id, %{"token" => token})
  end

  test "a join with a bad token gives a new player", %{id: id} do
    {:ok, %{player_id: player_id}, _socket} = join_game(id)

    assert {:ok, %{player_id: other_id}, _socket} = join_game(id, %{"token" => "bad"})
    assert other_id != player_id
  end

  test "the channel joins again when the game process stops", %{id: id, pid: pid} do
    {:ok, _reply, _socket} = join_game(id)

    # As when the node of the game stops
    Process.exit(pid, :kill)

    assert_push "joined", %{state: %{players_needed: 2}}
  end
end
