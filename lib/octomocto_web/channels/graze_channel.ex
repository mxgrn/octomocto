defmodule OctomoctoWeb.GrazeChannel do
  @moduledoc """
  Connects one browser to a Graze game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). Each change of the game is pushed as a
  `"state"` event, many times a second while the field runs. The browser
  of a player sends the place of its circle as `"steer"` events.
  """
  use Phoenix.Channel

  alias Octomocto.Graze
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [context: Graze, game: Graze.Game, salt: "graze player", kind: "graze"]

  @doc "The player id in the token of a player of the game, or nil."
  def player_id(game_id, token), do: GameChannel.verify_token(game_id, token, @game)

  @impl true
  def join("graze:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("steer", %{"x" => x, "y" => y, "t" => t}, socket)
      when is_number(x) and is_number(y) and is_integer(t) do
    Graze.steer(socket.assigns.game_id, socket.assigns.player_id, x, y, t)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Graze.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("next_game", _params, socket) do
    NextGame.start(socket, @game)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:graze_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
