defmodule OctomoctoWeb.GrazeChannelTest do
  # Not async: the game process reads the public id of the user (see
  # `Octomocto.Seats.add/7`), so it needs the shared sandbox
  use OctomoctoWeb.ChannelCase, async: false

  import Octomocto.GameHelpers

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!(graze_game(id))

    {:ok, reply, socket} =
      OctomoctoWeb.UserSocket
      |> socket()
      |> subscribe_and_join(OctomoctoWeb.GrazeChannel, "graze:" <> id)

    %{reply: reply, socket: socket}
  end

  test "join replies with the player id and the circle", %{reply: reply} do
    assert %{player_id: player_id, state: %{circles: [%{id: player_id}]}} = reply
  end

  test "steer moves the circle of the player", %{socket: socket} do
    assert_push "state", %{squares: [_ | _]}, 1000

    push(socket, "steer", %{"x" => 300, "y" => 500, "t" => System.system_time(:millisecond)})

    assert_push "state", %{circles: [%{x: 300.0}]}, 1000
  end
end
