defmodule OctomoctoWeb.AstronautChannelTest do
  use OctomoctoWeb.ChannelCase, async: true

  alias Octomocto.Astronaut.Game

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!({Game, id})
    %{id: id}
  end

  test "join replies with the player id and the game state", %{id: id} do
    {:ok, reply, _socket} =
      OctomoctoWeb.UserSocket
      |> socket()
      |> subscribe_and_join(OctomoctoWeb.AstronautChannel, "astronaut:" <> id)

    assert %{player_id: player_id, state: %{players: [%{id: player_id}]}} = reply
  end

  test "move pushes the new game state", %{id: id} do
    {:ok, _reply, socket} =
      OctomoctoWeb.UserSocket
      |> socket()
      |> subscribe_and_join(OctomoctoWeb.AstronautChannel, "astronaut:" <> id)

    push(socket, "move", %{"dir" => "north"})

    assert_push "state", %{players: [%{facing: :north}]}
  end

  test "join fails for an unknown game" do
    assert {:error, %{reason: "not_found"}} =
             OctomoctoWeb.UserSocket
             |> socket()
             |> subscribe_and_join(OctomoctoWeb.AstronautChannel, "astronaut:unknown")
  end
end
