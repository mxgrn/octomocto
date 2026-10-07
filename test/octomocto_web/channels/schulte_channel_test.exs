defmodule OctomoctoWeb.SchulteChannelTest do
  use OctomoctoWeb.ChannelCase, async: true

  alias Octomocto.Schulte.Game
  alias OctomoctoWeb.UserSocket

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!({Game, {id, :random}})
    %{id: id}
  end

  test "join replies with the player id and the game state", %{id: id} do
    {:ok, reply, _socket} =
      OctomoctoWeb.UserSocket
      |> socket()
      |> subscribe_and_join(OctomoctoWeb.SchulteChannel, "schulte:" <> id)

    assert %{player_id: player_id, state: %{players: [%{id: player_id}]}} = reply
  end

  test "pick pushes the new game state", %{id: id} do
    {:ok, _reply, socket} =
      OctomoctoWeb.UserSocket
      |> socket()
      |> subscribe_and_join(OctomoctoWeb.SchulteChannel, "schulte:" <> id)

    push(socket, "pick", %{"number" => 1})

    assert_push "state", %{next: 2}
  end

  test "connect gives the user id from a valid token, and nil for a guest" do
    {:ok, socket} = connect(OctomoctoWeb.UserSocket, %{"user_token" => UserSocket.user_token(42)})
    assert socket.assigns.user_id == 42

    {:ok, socket} = connect(OctomoctoWeb.UserSocket, %{"user_token" => "bad"})
    assert socket.assigns.user_id == nil
  end

  test "join fails for an unknown game" do
    assert {:error, %{reason: "not_found"}} =
             OctomoctoWeb.UserSocket
             |> socket()
             |> subscribe_and_join(OctomoctoWeb.SchulteChannel, "schulte:unknown")
  end
end
