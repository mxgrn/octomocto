defmodule OctomoctoWeb.SchulteChannelTest do
  # Not async: the game process reads the public id of the user (see
  # `Octomocto.Seats.add/7`), so it needs the shared sandbox
  use OctomoctoWeb.ChannelCase, async: false

  import Octomocto.GameHelpers

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!(schulte_game(id))

    {:ok, reply, socket} =
      OctomoctoWeb.UserSocket
      |> socket()
      |> subscribe_and_join(OctomoctoWeb.SchulteChannel, "schulte:" <> id)

    %{reply: reply, socket: socket}
  end

  test "join replies with the player id and the grid", %{reply: reply} do
    assert %{player_id: player_id, state: %{size: 5, players: [%{id: player_id}]}} = reply
  end

  test "pick pushes the new game state", %{socket: socket} do
    push(socket, "pick", %{"number" => 1})

    assert_push "state", %{next: 2}
  end

  test "restart pushes a new table with zero scores", %{socket: socket} do
    push(socket, "pick", %{"number" => 1})
    assert_push "state", %{next: 2}

    push(socket, "restart", %{})

    assert_push "state", %{next: 1, players: [%{score: 0}]}
  end
end
