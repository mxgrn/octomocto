defmodule OctomoctoWeb.SchulteChannel do
  @moduledoc """
  Connects one browser to a Schulte game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event.
  """
  use Phoenix.Channel

  alias Octomocto.Schulte
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [
    context: Schulte,
    game: Schulte.Game,
    # Not "schulte player", the salt of Nimble Mosaic when its name was
    # "Schulte"
    salt: "schulte_table player",
    kind: "schulte"
  ]

  @doc "The player id in the token of a player of the game, or nil."
  def player_id(game_id, token), do: GameChannel.verify_token(game_id, token, @game)

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
