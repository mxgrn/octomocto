defmodule OctomoctoWeb.MatchChannel do
  @moduledoc """
  Connects one browser to a Match game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). Each change of the game is pushed as a
  `"state"` event.
  """
  use Phoenix.Channel

  alias Octomocto.Match
  alias OctomoctoWeb.GameChannel

  @game [context: Match, game: Match.Game, salt: "match player"]

  @impl true
  def join("match:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("flip", %{"card" => card}, socket) when is_integer(card) do
    Match.flip(socket.assigns.game_id, socket.assigns.player_id, card)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Match.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:match_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
