defmodule Octomocto.GameProcess do
  @moduledoc """
  Finds the process of a game in the cluster. A game process is registered
  with `game.via(id)` and keeps a copy of its state in a
  `Octomocto.GameStore`. When no node runs the game (for example, its node
  stopped in a deploy), the game starts again on this node from that copy,
  under the `supervisor`.
  """

  @doc """
  Adds a player for the calling process with a `{:join, pid, user_id, name,
  player_id, guest_id}` call to the game, and gives the reply of the game.
  The `guest_id` is nil for a user (see `Octomocto.Guests`). Gives
  `{:error, :not_found}` when the game does not exist, and
  `{:error, :unavailable}` when the node of the game stopped a moment ago
  (try again soon).
  """
  def join(game, store, supervisor, id, user_id, name, player_id, guest_id) do
    call(game, store, supervisor, id, {:join, self(), user_id, name, player_id, guest_id})
  end

  @doc """
  Gives the reply of a `:watch` call to the game: the state for a process
  that only watches. Gives the same errors as `join/8`.
  """
  def watch(game, store, supervisor, id) do
    call(game, store, supervisor, id, :watch)
  end

  @doc """
  The reply of a game process to a `{:next_game, player_id, page}` call
  (see `OctomoctoWeb.NextGame`): the id of the next game and the new state.
  The first call creates the game with `page.create_default_game/2`, for
  the number of players and with the visibility of the game. The next
  calls give the same id. A restart must delete `:next_game` from the
  state. The id is nil for a player who is not in the game.
  """
  def next_game(state, player_id, page) when is_map_key(state.players, player_id) do
    state =
      Map.put_new_lazy(state, :next_game, fn ->
        page.create_default_game(map_size(state.players), state.public)
      end)

    {state.next_game, state}
  end

  def next_game(state, _player_id, _page), do: {nil, state}

  defp call(game, store, supervisor, id, request) do
    case whereis(game, store, supervisor, id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, request)
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp whereis(game, store, supervisor, id) do
    with nil <- GenServer.whereis(game.via(id)),
         %{} = state <- store.read(id) do
      case DynamicSupervisor.start_child(supervisor, {game, state}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end
    end
  end
end
