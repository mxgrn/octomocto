defmodule OctomoctoWeb.EchoChannel do
  @moduledoc """
  Connects one browser to an Echo game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). Each change of the game is pushed as a
  `"state"` event.
  """
  use Phoenix.Channel

  alias Octomocto.Echo
  alias OctomoctoWeb.GameChannel

  @game [context: Echo, game: Echo.Game, salt: "echo player"]

  @impl true
  def join("echo:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("start", _params, socket) do
    Echo.start(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("press", %{"pad" => pad}, socket) when is_integer(pad) do
    Echo.press(socket.assigns.game_id, socket.assigns.player_id, pad)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Echo.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:echo_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
