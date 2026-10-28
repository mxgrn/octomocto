defmodule OctomoctoWeb.SnapChannel do
  @moduledoc """
  Connects one browser to a Snap game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). Each change of the game is pushed as a
  `"state"` event. An `"answer"` has the index of the card, so that an
  answer that comes twice counts once.
  """
  use Phoenix.Channel

  alias Octomocto.Snap
  alias OctomoctoWeb.GameChannel

  @game [context: Snap, game: Snap.Game, salt: "snap player", kind: "snap"]

  @impl true
  def join("snap:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("answer", %{"index" => index, "same" => same}, socket)
      when is_integer(index) and is_boolean(same) do
    Snap.answer(socket.assigns.game_id, socket.assigns.player_id, index, same)
    {:noreply, socket}
  end

  def handle_in("time_up", _params, socket) do
    Snap.time_up(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Snap.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:snap_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
