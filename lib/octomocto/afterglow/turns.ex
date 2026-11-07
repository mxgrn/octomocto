defmodule Octomocto.Afterglow.Turns do
  @moduledoc """
  Afterglow for 2 to 4 players, who take turns and make one pattern
  together (see `Octomocto.Afterglow.TurnGame`). Each game is a process on
  one node of the cluster, found by its id. A copy of its state is in
  `Octomocto.Afterglow.TurnStore`, so the game continues on another node
  when its node stops. The results are saved with the results of the
  single-player games, see `Octomocto.Afterglow`.
  """

  alias Octomocto.Afterglow.{TurnGame, TurnStore}
  alias Octomocto.{GameProcess, Match}

  @doc """
  Starts a new game and returns its id. The `config` has the `:size` of
  the grid, the number of `:players` and `:public` (a public game is in the
  lists of the settings page).
  """
  def create_game(config) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Octomocto.Afterglow.TurnSupervisor,
        {TurnGame, {id, config}}
      )

    id
  end

  @doc "Adds a player for the calling process, as `Octomocto.Echo.join/6` does."
  def join(
        id,
        user_id \\ nil,
        name \\ nil,
        player_id \\ nil,
        guest_id \\ nil,
        from_lobby \\ false
      ) do
    GameProcess.join(
      TurnGame,
      TurnStore,
      Octomocto.Afterglow.TurnSupervisor,
      id,
      user_id,
      name,
      player_id,
      guest_id,
      from_lobby
    )
  end

  @doc "Gives the state of the game to a process that only watches."
  def watch(id) do
    GameProcess.watch(TurnGame, TurnStore, Octomocto.Afterglow.TurnSupervisor, id)
  end

  @doc "The player clicks a tile. Only the player of the turn can."
  def tap(id, player_id, cell) when is_integer(cell) do
    GenServer.cast(TurnGame.via(id), {:tap, player_id, cell})
  end

  @doc """
  Starts the next game of the match at once, with the same players on the
  next larger grid (see `next_size` in `TurnGame.public_field/1`). Only a
  player of a finished game can, and the calling process must hold the
  seat of the player (the channel of the player). Gives `:ok` or
  `{:error, reason}`.
  """
  def play_larger(id, player_id) do
    with {:ok, %{next_size: size}} when is_integer(size) <-
           Match.edit_settings(TurnGame, id, player_id) do
      Match.change_settings(TurnGame, id, player_id, %{size: size})
    else
      {:ok, _state} -> {:error, :not_allowed}
      error -> error
    end
  end

  @doc "Starts a new game with the same settings and players. Only a player can."
  def restart(id, player_id) do
    GenServer.cast(TurnGame.via(id), {:restart, player_id})
  end
end
