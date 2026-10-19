defmodule OctomoctoWeb.SchulteChannel do
  @moduledoc """
  Connects one browser to a Schulte game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event.
  """
  use Phoenix.Channel

  alias Octomocto.Schulte
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [context: Schulte, game: Schulte.Game, salt: "schulte player", kind: "schulte"]

  @impl true
  def join("schulte:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("pick", %{"number" => number}, socket) when is_integer(number) do
    Schulte.pick(socket.assigns.game_id, socket.assigns.player_id, number)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Schulte.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("next_game", _params, socket) do
    NextGame.start(socket, @game)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:schulte_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
