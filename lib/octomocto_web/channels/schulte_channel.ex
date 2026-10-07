defmodule OctomoctoWeb.SchulteChannel do
  @moduledoc """
  Connects one browser to a Schulte game. Each join adds a new player (a
  guest when the socket has no user). The join reply has the player id and
  the full game state, and each later change is pushed as a `"state"` event.
  The player id is nil when the game is full: then the browser only watches.
  """
  use Phoenix.Channel

  alias Octomocto.Schulte
  alias Octomocto.Schulte.Game

  @impl true
  def join("schulte:" <> game_id, _params, socket) do
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(game_id))

    case Schulte.join(game_id, socket.assigns[:user_id]) do
      {:ok, player_id, state} ->
        socket = assign(socket, game_id: game_id, player_id: player_id)
        {:ok, %{player_id: player_id, state: state}, socket}

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("pick", %{"number" => number}, socket) when is_integer(number) do
    Schulte.pick(socket.assigns.game_id, socket.assigns.player_id, number)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Schulte.restart(socket.assigns.game_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:schulte_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end
end
