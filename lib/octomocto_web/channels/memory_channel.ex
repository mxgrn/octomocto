defmodule OctomoctoWeb.MemoryChannel do
  @moduledoc """
  Connects one browser to a Memory game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). Each change of the game is pushed as a
  `"state"` event.
  """
  use Phoenix.Channel

  alias Octomocto.Memory
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [context: Memory, game: Memory.Game, salt: "memory player", kind: "memory"]

  @impl true
  def join("memory:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("flip", %{"card" => card}, socket) when is_integer(card) do
    Memory.flip(socket.assigns.game_id, socket.assigns.player_id, card)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Memory.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("next_game", _params, socket) do
    NextGame.start(socket, @game)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:memory_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
