defmodule Octomocto.Penguin do
  @moduledoc """
  Multiplayer penguin maze games. Each game is a `Octomocto.Penguin.Game`
  process, found by its id.
  """

  alias Octomocto.Penguin.Game

  @doc "Starts a new game and returns its id."
  def create_game do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    {:ok, _pid} = DynamicSupervisor.start_child(Octomocto.Penguin.GameSupervisor, {Game, id})
    id
  end

  def game_exists?(id) do
    Registry.lookup(Octomocto.Penguin.Registry, id) != []
  end

  @doc """
  Adds a penguin for the calling process. The penguin is removed when the
  process stops. Subscribe to `Game.topic(id)` first to get all updates.
  """
  def join(id) do
    if game_exists?(id) do
      GenServer.call(Game.via(id), {:join, self()})
    else
      {:error, :not_found}
    end
  end

  def move(id, player_id, dir) when dir in [:north, :east, :south, :west] do
    GenServer.cast(Game.via(id), {:move, player_id, dir})
  end
end
