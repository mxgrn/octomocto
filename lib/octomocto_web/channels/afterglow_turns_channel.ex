defmodule OctomoctoWeb.AfterglowTurnsChannel do
  @moduledoc """
  Connects one browser to an Afterglow game with turns (see
  `OctomoctoWeb.GameChannel` for the join and the rejoin). Each change of
  the game is pushed as a `"state"` event, and the flash of the full
  pattern after a new tile as a `"flash"` event.
  """
  use Phoenix.Channel

  alias Octomocto.Afterglow.{TurnGame, Turns}
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [context: Turns, game: TurnGame, salt: "afterglow turns player", kind: "afterglow"]

  @doc "The player id in the token of a player of the game, or nil."
  def player_id(game_id, token), do: GameChannel.verify_token(game_id, token, @game)

  @impl true
  def join("afterglow_turns:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("tap", %{"cell" => cell}, socket) when is_integer(cell) do
    Turns.tap(socket.assigns.game_id, socket.assigns.player_id, cell)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Turns.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("play_larger", _params, socket) do
    Turns.play_larger(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("next_game", _params, socket) do
    NextGame.start(socket, @game)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:afterglow_turns_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info({:afterglow_turns_flash, pattern}, socket) do
    push(socket, "flash", %{pattern: pattern})
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
