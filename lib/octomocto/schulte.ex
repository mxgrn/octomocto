defmodule Octomocto.Schulte do
  @moduledoc """
  Multiplayer Schulte tables. Each game is a `Octomocto.Schulte.Game`
  process, found by its id.
  """

  alias Octomocto.Schulte.Game

  @doc "Starts a new game and returns its id."
  def create_game do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    {:ok, _pid} = DynamicSupervisor.start_child(Octomocto.Schulte.GameSupervisor, {Game, id})
    id
  end

  def game_exists?(id) do
    Registry.lookup(Octomocto.Schulte.Registry, id) != []
  end

  @doc """
  Adds a player for the calling process. The player is removed when the
  process stops. Subscribe to `Game.topic(id)` first to get all updates.
  """
  def join(id) do
    if game_exists?(id) do
      GenServer.call(Game.via(id), {:join, self()})
    else
      {:error, :not_found}
    end
  end

  @doc "The player clicks a number. Only the next number counts."
  def pick(id, player_id, number) when is_integer(number) do
    GenServer.cast(Game.via(id), {:pick, player_id, number})
  end

  @doc "Starts a new field with zero scores, after all numbers are found."
  def restart(id) do
    GenServer.cast(Game.via(id), :restart)
  end
end
