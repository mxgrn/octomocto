defmodule OctomoctoWeb.NimbleMosaicChannel do
  @moduledoc """
  Connects one browser to a Nimble Mosaic game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event.
  """
  use Phoenix.Channel

  alias Octomocto.NimbleMosaic
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [
    context: NimbleMosaic,
    game: NimbleMosaic.Game,
    salt: "nimble_mosaic player",
    kind: "nimble-mosaic"
  ]

  @doc "The player id in the token of a player of the game, or nil."
  def player_id(game_id, token), do: GameChannel.verify_token(game_id, token, @game)

  @impl true
  def join("nimble-mosaic:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("pick", %{"number" => number}, socket) when is_integer(number) do
    NimbleMosaic.pick(socket.assigns.game_id, socket.assigns.player_id, number)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    NimbleMosaic.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("next_game", _params, socket) do
    NextGame.start(socket, @game)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:nimble_mosaic_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
