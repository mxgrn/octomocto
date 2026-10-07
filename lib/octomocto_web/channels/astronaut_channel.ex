defmodule OctomoctoWeb.AstronautChannel do
  @moduledoc """
  Connects one browser to an astronaut game. Each join adds a new astronaut. The
  join reply has the player id and the full game state, and each later
  change is pushed as a `"state"` event.
  """
  # Moves come in several times a second, so do not log each one.
  use Phoenix.Channel, log_handle_in: false

  alias Octomocto.Astronaut
  alias Octomocto.Astronaut.Game

  @dirs %{"north" => :north, "east" => :east, "south" => :south, "west" => :west}

  @impl true
  def join("astronaut:" <> game_id, _params, socket) do
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(game_id))

    case Astronaut.join(game_id) do
      {:ok, player_id, state} ->
        socket = assign(socket, game_id: game_id, player_id: player_id)
        {:ok, %{player_id: player_id, state: state}, socket}

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("move", %{"dir" => dir}, socket) when is_map_key(@dirs, dir) do
    Astronaut.move(socket.assigns.game_id, socket.assigns.player_id, @dirs[dir])
    {:noreply, socket}
  end

  @impl true
  def handle_info({:astronaut_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end
end
