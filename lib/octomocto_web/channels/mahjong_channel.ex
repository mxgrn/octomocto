defmodule OctomoctoWeb.MahjongChannel do
  @moduledoc """
  Connects one browser to a mahjong game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event. The reply to a `"remove"` tells if the pair went off the
  board, so that the browser can clear the selection.
  """
  use Phoenix.Channel

  alias Octomocto.Mahjong
  alias OctomoctoWeb.GameChannel

  @game [context: Mahjong, game: Mahjong.Game, salt: "mahjong player"]

  @impl true
  def join("mahjong:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("remove", %{"a" => a, "b" => b}, socket) when is_integer(a) and is_integer(b) do
    result = Mahjong.remove(socket.assigns.game_id, socket.assigns.player_id, a, b)
    {:reply, {:ok, %{result: result}}, socket}
  end

  def handle_in("shuffle", _params, socket) do
    Mahjong.shuffle(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Mahjong.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:mahjong_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
