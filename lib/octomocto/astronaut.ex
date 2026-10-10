defmodule Octomocto.Astronaut do
  @moduledoc """
  Multiplayer astronaut maze games. Each game is an `Octomocto.Astronaut.Game`
  process, found by its id.
  """

  alias Octomocto.Astronaut.Game

  @doc "Starts a new game and returns its id."
  def create_game do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    {:ok, _pid} = DynamicSupervisor.start_child(Octomocto.Astronaut.GameSupervisor, {Game, id})
    id
  end

  def game_exists?(id) do
    GenServer.whereis(Game.via(id)) != nil
  end

  @doc """
  Adds an astronaut for the calling process. The astronaut is removed when the
  process stops. Subscribe to `Game.topic(id)` first to get all updates.
  The `name` is the display name, or nil for a color name.
  """
  def join(id, name \\ nil) do
    if game_exists?(id) do
      GenServer.call(Game.via(id), {:join, self(), name})
    else
      {:error, :not_found}
    end
  end

  def move(id, player_id, dir) when dir in [:north, :east, :south, :west] do
    GenServer.cast(Game.via(id), {:move, player_id, dir})
  end
end
