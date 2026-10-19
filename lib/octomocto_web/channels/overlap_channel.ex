defmodule OctomoctoWeb.OverlapChannel do
  @moduledoc """
  Connects one browser to an Overlap game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event. A `"tap"` has the ids of the two cards on the table, so
  that a late tap on old cards does nothing.
  """
  use Phoenix.Channel

  alias Octomocto.Overlap
  alias OctomoctoWeb.GameChannel

  @game [context: Overlap, game: Overlap.Game, salt: "overlap player"]

  @impl true
  def join("overlap:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("tap", %{"pile" => pile, "card" => card, "symbol" => symbol}, socket)
      when is_integer(pile) and is_integer(card) and is_integer(symbol) do
    Overlap.tap(socket.assigns.game_id, socket.assigns.player_id, pile, card, symbol)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Overlap.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:overlap_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
