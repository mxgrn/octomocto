defmodule OctomoctoWeb.SetGameChannel do
  @moduledoc """
  Connects one browser to a Set game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). Each change of the game is pushed as a
  `"state"` event.
  """
  use Phoenix.Channel

  alias Octomocto.SetGame
  alias OctomoctoWeb.GameChannel

  @game [context: SetGame, game: SetGame.Game, salt: "set player"]

  @impl true
  def join("set:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("claim", %{"cards" => [a, b, c] = cards}, socket)
      when is_integer(a) and is_integer(b) and is_integer(c) do
    SetGame.claim(socket.assigns.game_id, socket.assigns.player_id, cards)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    SetGame.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:set_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
