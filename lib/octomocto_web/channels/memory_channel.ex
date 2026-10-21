defmodule OctomoctoWeb.MemoryChannel do
  @moduledoc """
  Connects one browser to a Memory game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). Each change of the game is pushed as a
  `"state"` event. After a level of the campaign with no slip, the player
  starts the next level with `"next_level"`: the reply has the id of its
  game.
  """
  use Phoenix.Channel

  alias Octomocto.Memory
  alias Octomocto.Memory.{Campaign, Store}
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [context: Memory, game: Memory.Game, salt: "memory player", kind: "memory"]

  @doc "The player id in the token of a player of the game, or nil."
  def player_id(game_id, token), do: GameChannel.verify_token(game_id, token, @game)

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

  # The next level has the same theme choice
  def handle_in("next_level", _params, socket) do
    user_id = socket.assigns.user_id

    with %{campaign: %{user_id: ^user_id} = campaign, failed: false} = state <-
           Store.read(socket.assigns.game_id),
         true <- state.finished_at != nil,
         {:ok, id} <- Campaign.start(user_id, campaign.level + 1, campaign.theme) do
      {:reply, {:ok, %{id: id}}, socket}
    else
      _ -> {:reply, {:error, %{}}, socket}
    end
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
