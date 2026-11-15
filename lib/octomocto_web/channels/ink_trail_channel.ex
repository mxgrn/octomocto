defmodule OctomoctoWeb.InkTrailChannel do
  @moduledoc """
  Connects one browser to a Ink Trail game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event. A `"tap"` has the step of the path, so that a tap that
  comes twice counts once.
  """
  use Phoenix.Channel

  alias Octomocto.InkTrail
  alias OctomoctoWeb.GameChannel

  @game [context: InkTrail, game: InkTrail.Game, salt: "ink_trail player", kind: "ink-trail"]

  @impl true
  def join("ink-trail:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("tap", %{"step" => step, "cave" => cave}, socket)
      when is_integer(step) and is_integer(cave) do
    InkTrail.tap(socket.assigns.game_id, socket.assigns.player_id, step, cave)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    InkTrail.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ink_trail_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
