defmodule OctomoctoWeb.AfterglowChannel do
  @moduledoc """
  Connects one browser to an Afterglow game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event. A `"tap"` has the round, so that a click that comes late
  does not count in the next round.
  """
  use Phoenix.Channel

  alias Octomocto.Afterglow
  alias OctomoctoWeb.GameChannel

  @game [context: Afterglow, game: Afterglow.Game, salt: "afterglow player", kind: "afterglow"]

  @impl true
  def join("afterglow:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("tap", %{"round" => round, "cell" => cell}, socket)
      when is_integer(round) and is_integer(cell) do
    Afterglow.tap(socket.assigns.game_id, socket.assigns.player_id, round, cell)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Afterglow.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:afterglow_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
