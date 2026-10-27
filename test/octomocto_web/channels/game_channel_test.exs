defmodule OctomoctoWeb.GameChannelTest do
  # The Schulte channel uses OctomoctoWeb.GameChannel for the join and the
  # rejoin
  use OctomoctoWeb.ChannelCase, async: true

  alias Octomocto.Schulte.Game
  alias OctomoctoWeb.{SchulteChannel, UserSocket}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!({Game, {id, :random, :easy, 2, false}})
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

  test "a join with watch: true only watches, also when the game has a free seat", %{id: id} do
    assert {:ok, %{player_id: nil, token: nil, state: %{players: []}}, _socket} =
             join_game(id, %{"watch" => true})
  end

  test "a join of a full game only watches", %{id: id} do
    {:ok, _reply, _socket} = join_game(id)
    {:ok, _reply, _socket} = join_game(id)

    assert {:ok, %{player_id: nil, token: nil}, _socket} = join_game(id)
  end

  test "a watcher is counted, and the channels get the new count", %{id: id} do
    {:ok, %{watchers: 0}, _socket} = join_game(id)

    assert {:ok, %{watchers: 1}, _socket} = join_game(id, %{"watch" => true})
    assert_push "watchers", %{count: 1}
  end

  test "next_game sends all players, but not the watchers, to the same next game", %{id: id} do
    {:ok, _reply, socket} = join_game(id)
    {:ok, _reply, _socket} = join_game(id)
    {:ok, _reply, _socket} = join_game(id, %{"watch" => true})

    push(socket, "next_game", %{})

    assert_push "next_game", %{id: next_id}
    assert_push "next_game", %{id: ^next_id}
    refute_push "next_game", _
  end

  test "the channel joins again when the game process stops", %{id: id, pid: pid} do
    {:ok, _reply, _socket} = join_game(id)

    # As when the node of the game stops
    Process.exit(pid, :kill)

    assert_push "joined", %{state: %{players_needed: 2}}
  end
end
